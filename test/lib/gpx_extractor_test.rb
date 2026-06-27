require "test_helper"

class GpxExtractorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @gpx = Rails.root.join("test/fixtures/files/gpx/ride.gpx").read
  end

  def extract(activity = @user.activities.build)
    GpxExtractor.new(activity, reverse_geocode: false).extract(@gpx)
    activity
  end

  test "builds a data point per track point" do
    activity = extract
    assert_equal 5, activity.activity_data_points.size
  end

  test "computes distance from track points via haversine" do
    activity = extract
    assert_in_delta 496.8, activity.distance.to_f, 1.0
  end

  test "computes elevation gain with a noise threshold" do
    # 44.5 -> 46.0 (+1.5, below 3m threshold, ignored) -> 52.0 (+7.5) -> 49.0 -> 58.0 (+9.0)
    activity = extract
    assert_in_delta 16.5, activity.total_elevation_gain.to_f, 0.1
  end

  test "computes moving time as active_time" do
    activity = extract
    assert_equal "PT40S", activity.active_time
  end

  test "sets start and end time from first/last point" do
    activity = extract
    assert_equal Time.utc(2026, 3, 29, 7, 49, 28), activity.start_time
    assert_equal Time.utc(2026, 3, 29, 7, 50, 8), activity.end_time
  end

  test "records max speed and per-point metrics" do
    activity = extract
    assert_operator activity.max_speed.to_f, :>, 0
    assert_equal 110, activity.activity_data_points.first.heart_rate
    assert_equal 44.5, activity.activity_data_points.first.altitude.to_f
  end

  test "builds a PostGIS LineString path" do
    activity = extract
    assert_kind_of RGeo::Feature::LineString, activity.path
    assert_equal 5, activity.path.num_points
  end

  test "falls back to name and sport from the GPX track" do
    activity = extract
    assert_equal "Petite sortie GPX", activity.name
    assert_equal "mountain_bike_ride", activity.sport
  end

  test "does not override a sport already set on the activity" do
    activity = extract(@user.activities.build(sport: :gravel_ride))
    assert_equal "gravel_ride", activity.sport
  end

  test "persists end to end" do
    activity = extract
    assert activity.save, activity.errors.full_messages.to_sentence
    assert_equal 5, activity.reload.activity_data_points.count
  end

  # --- Native recorder contract (issue #48) ---------------------------------
  # The iOS/Android recorders serialize an on-device recording to GPX 1.1 and
  # upload it through POST /activities, which routes .gpx to GpxExtractor. These
  # tests pin the schema the apps must emit (see the device fixture and
  # docs/native-recording/s0-gpx-upload-contract.md) and prove it round-trips.

  def extract_native(activity = @user.activities.build)
    gpx = Rails.root.join("test/fixtures/files/gpx/native_recording.gpx").read
    GpxExtractor.new(activity, reverse_geocode: false).extract(gpx)
    activity
  end

  test "device-style GPX builds one data point per track point" do
    activity = extract_native
    assert_equal 10, activity.activity_data_points.size
    assert_kind_of RGeo::Feature::LineString, activity.path
    assert_equal 10, activity.path.num_points
  end

  test "device-style GPX carries hr, cadence and power per point" do
    points = extract_native.activity_data_points

    assert_equal 112, points.first.heart_rate
    assert_equal 84.0, points.first.cadence.to_f
    assert_equal 180.0, points.first.power.to_f
    assert_equal 35.0, points.first.altitude.to_f

    assert_equal 130, points.last.heart_rate
    assert_equal 87.0, points.last.cadence.to_f
    assert_equal 185.0, points.last.power.to_f
  end

  test "device-style GPX maps <trk><type> onto the sport enum" do
    activity = extract_native
    assert_equal "bike", activity.sport
    assert_equal "Sortie enregistrée sur le téléphone", activity.name
  end

  test "an explicit activity[sport] is not overridden by <trk><type>" do
    # The device UX picks the sport; create() sets it from the param before the
    # extractor runs, and the GPX <type> is only a fallback (||=).
    activity = extract_native(@user.activities.build(sport: :gravel_ride))
    assert_equal "gravel_ride", activity.sport
  end

  test "device-style GPX derives summary metrics and timestamps" do
    activity = extract_native

    assert_equal Time.utc(2026, 6, 25, 8, 0, 0), activity.start_time
    assert_equal Time.utc(2026, 6, 25, 8, 0, 9), activity.end_time
    assert_in_delta 50.1, activity.distance.to_f, 1.0
    assert_equal "PT9S", activity.active_time
    assert_operator activity.max_speed.to_f, :>, 0
  end

  test "device-style GPX persists end to end" do
    activity = extract_native
    activity.name ||= "Sans nom"
    assert activity.save, activity.errors.full_messages.to_sentence
    assert_equal 10, activity.reload.activity_data_points.count
  end

  test "filters an isolated GPS spike so max_speed stays plausible" do
    # 21 points 1s apart progressing steadily north (~2 m/s), except point #10
    # is displaced ~55m east — a GPS spike reading as ~55 m/s on the way out and
    # back. The surrounding steady points let the Hampel filter flag it.
    rows = (0..20).map do |i|
      lat = 45.0 + (i * 0.00002)
      lon = i == 10 ? 5.0007 : 5.0
      time = (Time.utc(2026, 1, 1, 10) + i).iso8601
      %(<trkpt lat="#{lat}" lon="#{lon}"><time>#{time}</time></trkpt>)
    end
    gpx = %(<?xml version="1.0"?><gpx><trk><type>cycling</type><trkseg>#{rows.join}</trkseg></trk></gpx>)

    activity = @user.activities.build(sport: :bike)
    GpxExtractor.new(activity, reverse_geocode: false).extract(gpx)

    assert_operator activity.max_speed.to_f, :<, 10, "the ~55 m/s spike should be filtered out"
    assert_nil activity.activity_data_points[10].speed, "spike-out speed should be nulled"
    assert_nil activity.activity_data_points[11].speed, "spike-return speed should be nulled"
    assert_equal 21, activity.activity_data_points.size, "all points kept; only spike speeds dropped"
  end

  test "a single-point track has no path but still persists" do
    # A native recording stopped almost immediately (or one with a single GPS
    # fix) yields one point. A LineString needs >= 2 vertices, so the path stays
    # nil rather than raising RGeo::Error::InvalidGeometry on save.
    gpx = %(<?xml version="1.0"?><gpx><trk><type>cycling</type><trkseg>) +
          %(<trkpt lat="48.8566" lon="2.3522"><time>2026-06-25T08:00:00Z</time></trkpt>) +
          %(</trkseg></trk></gpx>)

    activity = @user.activities.build(sport: :bike, name: "Une seconde")
    GpxExtractor.new(activity, reverse_geocode: false).extract(gpx)

    assert_equal 1, activity.activity_data_points.size
    assert_nil activity.path
    assert activity.save, activity.errors.full_messages.to_sentence
  end
end
