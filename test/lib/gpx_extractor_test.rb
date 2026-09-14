require "test_helper"

# Extraction facts only: what a GPX file yields as a Track. How a Track is
# applied to an Activity (path geometry, name/sport precedence, location
# fallback) is ActivityIngestionTest's job.
class GpxExtractorTest < ActiveSupport::TestCase
  setup do
    @gpx = Rails.root.join("test/fixtures/files/gpx/ride.gpx").read
  end

  def track(gpx = @gpx)
    GpxExtractor.new(gpx).extract
  end

  test "builds a point per timestamped track point" do
    assert_equal 5, track.points.size
  end

  test "computes distance from track points via haversine" do
    assert_in_delta 496.8, track.summary.distance, 1.0
  end

  test "computes elevation gain with a noise threshold" do
    # 44.5 -> 46.0 (+1.5, below 3m threshold, ignored) -> 52.0 (+7.5) -> 49.0 -> 58.0 (+9.0)
    assert_in_delta 16.5, track.summary.elevation_gain, 0.1
  end

  test "computes moving time" do
    assert_equal 40, track.summary.moving_seconds
  end

  test "sets start and end time from first/last point" do
    assert_equal Time.utc(2026, 3, 29, 7, 49, 28), track.summary.start_time
    assert_equal Time.utc(2026, 3, 29, 7, 50, 8), track.summary.end_time
  end

  test "records max speed and per-point metrics" do
    result = track
    assert_operator result.summary.max_speed, :>, 0
    assert_equal 110, result.points.first.heart_rate
    assert_equal 44.5, result.points.first.altitude
  end

  test "suggests a name and sport from the GPX track" do
    assert_equal "Petite sortie GPX", track.suggested_name
    assert_equal :mountain_bike_ride, track.suggested_sport
  end

  test "suggests no sport when the track carries no type" do
    gpx = %(<?xml version="1.0"?><gpx><trk><trkseg>) +
          %(<trkpt lat="48.8566" lon="2.3522"><time>2026-06-25T08:00:00Z</time></trkpt>) +
          %(</trkseg></trk></gpx>)

    assert_nil track(gpx).suggested_sport
  end

  # --- Native recorder contract (issue #48) ---------------------------------
  # The iOS/Android recorders serialize an on-device recording to GPX 1.1 and
  # upload it through POST /activities. These pin the schema the apps must emit
  # (see docs/native-recording/s0-gpx-upload-contract.md).

  def native_track
    track(Rails.root.join("test/fixtures/files/gpx/native_recording.gpx").read)
  end

  test "device-style GPX yields one point per track point" do
    assert_equal 10, native_track.points.size
  end

  test "device-style GPX carries hr, cadence and power per point" do
    points = native_track.points

    assert_equal 112, points.first.heart_rate
    assert_equal 84.0, points.first.cadence
    assert_equal 180.0, points.first.power
    assert_equal 35.0, points.first.altitude

    assert_equal 130, points.last.heart_rate
    assert_equal 87.0, points.last.cadence
    assert_equal 185.0, points.last.power
  end

  test "device-style GPX maps <trk><type> onto the sport enum" do
    assert_equal :bike, native_track.suggested_sport
    assert_equal "Sortie enregistrée sur le téléphone", native_track.suggested_name
  end

  test "device-style GPX derives summary metrics and timestamps" do
    summary = native_track.summary

    assert_equal Time.utc(2026, 6, 25, 8, 0, 0), summary.start_time
    assert_equal Time.utc(2026, 6, 25, 8, 0, 9), summary.end_time
    assert_in_delta 50.1, summary.distance, 1.0
    assert_equal 9, summary.moving_seconds
    assert_operator summary.max_speed, :>, 0
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
    result = track(%(<?xml version="1.0"?><gpx><trk><trkseg>#{rows.join}</trkseg></trk></gpx>))

    assert_operator result.summary.max_speed, :<, 10, "the ~55 m/s spike should be filtered out"
    assert_nil result.points[10].speed, "spike-out speed should be nulled"
    assert_nil result.points[11].speed, "spike-return speed should be nulled"
    assert_equal 21, result.points.size, "all points kept; only spike speeds dropped"
  end

  # --- Route-style GPX (no timestamps) --------------------------------------
  # The planner seeds waypoints from files that were never recordings, so
  # parse_points has to stay permissive about <time>. #extract is the filter.

  def route_gpx
    Rails.root.join("test/fixtures/files/gpx/route_no_time.gpx").read
  end

  test "parse_points keeps points that carry no time" do
    points = GpxExtractor.new(route_gpx).parse_points

    assert_equal 6, points.size
    assert points.all? { |point| point[:time].nil? }
    assert_in_delta 2.3522, points.first[:lon], 0.000001
    assert_in_delta 48.8566, points.first[:lat], 0.000001
  end

  test "parse_points tolerates an unparsable time" do
    gpx = %(<?xml version="1.0"?><gpx><trk><trkseg>) +
          %(<trkpt lat="48.8566" lon="2.3522"><time>pas une date</time></trkpt>) +
          %(</trkseg></trk></gpx>)

    points = GpxExtractor.new(gpx).parse_points

    assert_equal 1, points.size
    assert_nil points.first[:time]
  end

  # recorded_at is NOT NULL and the summary does timestamp arithmetic, so a
  # timeless point can never become a Track point.
  test "extract yields an empty track when no point carries a time" do
    result = nil
    assert_nothing_raised { result = track(route_gpx) }

    assert_empty result.points
    assert_nil result.summary.start_time
    assert_equal 0.0, result.summary.distance
  end

  test "extract keeps only the timestamped points of a mixed track" do
    gpx = %(<?xml version="1.0"?><gpx><trk><trkseg>) +
          %(<trkpt lat="48.8566" lon="2.3522"><time>2026-06-25T08:00:00Z</time></trkpt>) +
          %(<trkpt lat="48.8567" lon="2.3523"/>) +
          %(<trkpt lat="48.8568" lon="2.3524"><time>2026-06-25T08:00:10Z</time></trkpt>) +
          %(<trkpt lat="48.8569" lon="2.3525"/>) +
          %(<trkpt lat="48.8570" lon="2.3526"><time>2026-06-25T08:00:20Z</time></trkpt>) +
          %(</trkseg></trk></gpx>)

    result = track(gpx)

    assert_equal 3, result.points.size
    assert_equal Time.utc(2026, 6, 25, 8, 0, 0), result.summary.start_time
    assert_equal Time.utc(2026, 6, 25, 8, 0, 20), result.summary.end_time
  end

  # --- <rte>/<rtept> exports -------------------------------------------------

  test "parse_points falls back to rtept when there is no track" do
    gpx = Rails.root.join("test/fixtures/files/gpx/route_rtept.gpx").read
    points = GpxExtractor.new(gpx).parse_points

    assert_equal 4, points.size
    assert_in_delta 48.8626, points.last[:lat], 0.000001
  end

  test "parse_points prefers trkpt when a document carries both" do
    gpx = %(<?xml version="1.0"?><gpx>) +
          %(<trk><trkseg><trkpt lat="1.0" lon="1.0"/><trkpt lat="2.0" lon="2.0"/></trkseg></trk>) +
          %(<rte><rtept lat="3.0" lon="3.0"/><rtept lat="4.0" lon="4.0"/><rtept lat="5.0" lon="5.0"/></rte>) +
          %(</gpx>)

    points = GpxExtractor.new(gpx).parse_points

    assert_equal 2, points.size
    assert_in_delta 1.0, points.first[:lat], 0.000001
  end

  test "track_name falls back to the route name" do
    assert_equal "Boucle planifiée", GpxExtractor.new(route_gpx).track_name
    assert_equal "Itinéraire du dimanche",
                 GpxExtractor.new(Rails.root.join("test/fixtures/files/gpx/route_rtept.gpx").read).track_name
    assert_nil GpxExtractor.new(%(<?xml version="1.0"?><gpx><trk><trkseg/></trk></gpx>)).track_name
  end

  # --- gpx? ------------------------------------------------------------------
  # Nokogiri recovers rather than raising, so an arbitrary upload still yields a
  # document. Only the root element tells us whether it was really GPX.

  test "gpx? recognises a real gpx document" do
    assert GpxExtractor.new(@gpx).gpx?
    assert GpxExtractor.new(route_gpx).gpx?
  end

  test "gpx? rejects documents that are not gpx" do
    assert_not GpxExtractor.new("not xml at all").gpx?
    assert_not GpxExtractor.new("<html><body>hello</body></html>").gpx?
    assert_not GpxExtractor.new("").gpx?
  end
end
