require "test_helper"

# Application facts: how a Track becomes an Activity. What a file yields as a
# Track belongs to GpxExtractorTest / FitExtractorTest.
class ActivityIngestionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  teardown do
    restore_singleton_new(NominatimClient)
    restore_singleton_new(GpxExtractor)
  end

  def ingest(gpx, activity: @user.activities.build, filename: "ride.gpx", **options)
    ActivityIngestion.call(activity, StringIO.new(gpx), filename: filename,
                           reverse_geocode: false, **options)
  end

  def ride_gpx
    Rails.root.join("test/fixtures/files/gpx/ride.gpx").read
  end

  def two_point_gpx
    %(<?xml version="1.0"?><gpx><trk><type>cycling</type><trkseg>) +
      %(<trkpt lat="48.8566" lon="2.3522"><time>2026-06-25T08:00:00Z</time></trkpt>) +
      %(<trkpt lat="48.8570" lon="2.3526"><time>2026-06-25T08:00:10Z</time></trkpt>) +
      %(</trkseg></trk></gpx>)
  end

  # --- Format dispatch -------------------------------------------------------

  test "routes a .gpx filename to the GPX extractor" do
    activity = ingest(ride_gpx)

    assert_equal 5, activity.activity_data_points.size
    assert_equal "Petite sortie GPX", activity.name
  end

  test "routes any other filename to the FIT extractor" do
    fit = Rails.root.join("test/fixtures/files/fit/bike.fit").read
    activity = ingest(fit, activity: @user.activities.build(name: "Sortie", sport: :bike),
                           filename: "bike.fit")

    assert_equal 15_128, activity.activity_data_points.size
    assert_in_delta 65_570.71, activity.distance.to_f, 0.01
  end

  test "dispatches case-insensitively on the extension" do
    activity = ingest(ride_gpx, filename: "RIDE.GPX")

    assert_equal 5, activity.activity_data_points.size
  end

  # --- Effort score ----------------------------------------------------------

  test "scores the activity from its heart rate and the rider's max HR" do
    @user.update_columns(max_heart_rate: 200)
    activity = ingest(ride_gpx)

    # 10 s in Z1 (110 bpm) and 30 s in Z2 (120–135 bpm): 10/60 × 1 + 30/60 × 2
    assert_equal 1.2, activity.effort_score
    assert activity.effort_score_source_heart_rate?
  end

  test "leaves the score empty without a max HR" do
    activity = ingest(ride_gpx)

    assert_nil activity.effort_score
    assert_nil activity.effort_score_source
  end

  test "leaves the score empty without heart rate data" do
    @user.update_columns(max_heart_rate: 200)
    activity = ingest(two_point_gpx)

    assert_nil activity.effort_score
  end

  # --- Summary and data points ----------------------------------------------

  test "applies the track summary to the activity" do
    activity = ingest(ride_gpx)

    assert_in_delta 496.8, activity.distance.to_f, 1.0
    assert_in_delta 16.5, activity.total_elevation_gain.to_f, 0.1
    assert_equal "PT40S", activity.active_time
    assert_equal Time.utc(2026, 3, 29, 7, 49, 28), activity.start_time
    assert_equal Time.utc(2026, 3, 29, 7, 50, 8), activity.end_time
  end

  test "builds a data point per track point with its metrics" do
    point = ingest(ride_gpx).activity_data_points.first

    assert_equal 110, point.heart_rate
    assert_equal 44.5, point.altitude.to_f
    assert_not_nil point.location
  end

  test "always sets an active_time even when the track is empty" do
    # active_time is NOT NULL, so an empty track must not leave it blank.
    route = Rails.root.join("test/fixtures/files/gpx/route_no_time.gpx").read
    activity = ingest(route)

    assert_equal "PT0S", activity.active_time
    assert_nil activity.start_time
  end

  # --- Path geometry ---------------------------------------------------------

  test "builds a PostGIS LineString from the located points" do
    activity = ingest(ride_gpx)

    assert_kind_of RGeo::Feature::LineString, activity.path
    assert_equal 5, activity.path.num_points
  end

  test "a single-point track has no path but still persists" do
    # A LineString needs >= 2 vertices, so the path stays nil rather than raising
    # RGeo::Error::InvalidGeometry on save.
    gpx = %(<?xml version="1.0"?><gpx><trk><type>cycling</type><trkseg>) +
          %(<trkpt lat="48.8566" lon="2.3522"><time>2026-06-25T08:00:00Z</time></trkpt>) +
          %(</trkseg></trk></gpx>)

    activity = ingest(gpx, activity: @user.activities.build(sport: :bike, name: "Une seconde"))

    assert_equal 1, activity.activity_data_points.size
    assert_nil activity.path
    assert activity.save, activity.errors.full_messages.to_sentence
  end

  # --- Name and sport precedence --------------------------------------------

  test "takes name and sport from the file when the rider supplied none" do
    activity = ingest(two_point_gpx)

    assert_equal :bike, activity.sport.to_sym
  end

  test "a rider's own sport is not overridden by the file" do
    activity = ingest(ride_gpx, activity: @user.activities.build(sport: :gravel_ride))

    assert_equal "gravel_ride", activity.sport
  end

  test "a rider's own name is not overridden by the file" do
    activity = ingest(ride_gpx, activity: @user.activities.build(name: "Mon titre"))

    assert_equal "Mon titre", activity.name
  end

  # --- Location --------------------------------------------------------------

  test "falls back to Unknown when geocoding is off" do
    assert_equal "Unknown", ingest(ride_gpx).location
  end

  test "reverse geocodes the first located point when asked" do
    seen = []
    stub_geocoder { |lat, lon| seen << [ lat, lon ]; "Fontainebleau" }

    activity = ActivityIngestion.call(@user.activities.build, StringIO.new(ride_gpx),
                                      filename: "ride.gpx", reverse_geocode: true)

    assert_equal "Fontainebleau", activity.location
    assert_equal 1, seen.size, "should geocode once, from the first fix"
  end

  test "does not geocode a track with no located points" do
    route = Rails.root.join("test/fixtures/files/gpx/route_no_time.gpx").read
    stub_geocoder { |*| raise "should not geocode" }

    activity = ActivityIngestion.call(@user.activities.build, StringIO.new(route),
                                      filename: "route.gpx", reverse_geocode: true)

    assert_equal "Unknown", activity.location
  end

  # --- Time fallbacks (opt-in) ----------------------------------------------

  test "leaves times blank by default so a timeless upload still 422s" do
    route = Rails.root.join("test/fixtures/files/gpx/route_no_time.gpx").read
    activity = ingest(route, activity: @user.activities.build(sport: :bike, name: "Parcours"))

    assert_nil activity.start_time
    assert_not activity.valid?
  end

  test "applies a start fallback and defaults the end to it" do
    route = Rails.root.join("test/fixtures/files/gpx/route_no_time.gpx").read
    now = Time.utc(2026, 5, 1, 12)

    activity = ingest(route, fallback_start_time: now)

    assert_equal now, activity.start_time
    assert_equal now, activity.end_time
  end

  test "applies an explicit end fallback" do
    route = Rails.root.join("test/fixtures/files/gpx/route_no_time.gpx").read
    start = Time.utc(2026, 5, 1, 12)
    finish = Time.utc(2026, 5, 1, 13)

    activity = ingest(route, fallback_start_time: start, fallback_end_time: finish)

    assert_equal start, activity.start_time
    assert_equal finish, activity.end_time
  end

  test "a fallback never overrides a time the file supplied" do
    activity = ingest(ride_gpx, fallback_start_time: Time.utc(2000, 1, 1))

    assert_equal Time.utc(2026, 3, 29, 7, 49, 28), activity.start_time
  end

  # --- Problems --------------------------------------------------------------

  test "surfaces an extractor problem as an activity error" do
    # FitExtractor flags a course/workout file this way; the routing to an
    # activity error is what's under test here, not the flagging.
    track = Track.new(points: [], summary: Track::Summary.empty, problems: [ :invalid_file_type ])
    fake = Object.new
    fake.define_singleton_method(:extract) { track }
    GpxExtractor.define_singleton_method(:new) { |*| fake }

    activity = @user.activities.build
    ActivityIngestion.call(activity, StringIO.new(""), filename: "x.gpx", reverse_geocode: false)

    assert_includes activity.errors.details[:source_file].map { _1[:error] }, :invalid_file_type
  end

  # --- Default gear ----------------------------------------------------------

  test "gives an activity with no gear chosen its sport's default gear" do
    gears(:road_bike).update!(default_sports: %w[bike])

    activity = ingest(two_point_gpx, activity: @user.activities.build(sport: "bike"))

    assert_equal gears(:road_bike), activity.gear
  end

  test "picks the default for the sport the file suggests when the rider gave none" do
    gears(:road_bike).update!(default_sports: %w[bike])

    activity = ingest(two_point_gpx)

    assert_equal "bike", activity.sport
    assert_equal gears(:road_bike), activity.gear
  end

  test "keeps the gear the rider chose over the default" do
    gears(:road_bike).update!(default_sports: %w[bike])

    activity = ingest(two_point_gpx, activity: @user.activities.build(sport: "bike", gear: gears(:gravel_bike)))

    assert_equal gears(:gravel_bike), activity.gear
  end

  test "an explicit choice of no gear is not overridden by the default" do
    gears(:road_bike).update!(default_sports: %w[bike])

    activity = ingest(two_point_gpx, activity: @user.activities.build(sport: "bike"), gear_chosen: true)

    assert_nil activity.gear
  end

  test "leaves the gear empty when the sport has no default" do
    activity = ingest(two_point_gpx, activity: @user.activities.build(sport: "gravel_ride"))

    assert_nil activity.gear
  end

  # --- End to end ------------------------------------------------------------

  test "persists an ingested activity with its data points" do
    activity = ingest(ride_gpx)

    assert activity.save, activity.errors.full_messages.to_sentence
    assert_equal 5, activity.reload.activity_data_points.count
  end

  private

  # Follows the repo's existing stubbing idiom (see
  # planned_routes_controller_test.rb): swap the singleton `new`, remove it after.
  def stub_geocoder(&resolve)
    fake = Object.new
    fake.define_singleton_method(:reverse_geocode, &resolve)
    NominatimClient.define_singleton_method(:new) { fake }
  end

  def restore_singleton_new(klass)
    return unless klass.singleton_class.instance_methods(false).include?(:new)

    klass.singleton_class.remove_method(:new)
  end
end
