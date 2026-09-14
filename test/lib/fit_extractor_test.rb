require "test_helper"

# Extraction facts only: what a FIT file yields as a Track. Applying a Track to
# an Activity is ActivityIngestionTest's job.
class FitExtractorTest < ActiveSupport::TestCase
  def track(name = "bike")
    FitExtractor.new(Rails.root.join("test/fixtures/files/fit/#{name}.fit").read).extract
  end

  test "extracts a point per record message" do
    assert_equal 15_128, track.points.size
  end

  test "takes the summary from the device session message" do
    summary = track.summary

    assert_in_delta 65_570.71, summary.distance, 0.01
    assert_equal 597, summary.elevation_gain
    assert_equal 13_643, summary.moving_seconds
    assert_equal Time.utc(2026, 3, 8, 8, 52, 37), summary.start_time
    assert_equal Time.utc(2026, 3, 8, 13, 10, 55), summary.end_time
  end

  test "derives max_speed from the device's own per-point speeds" do
    # Unlike GPX, FIT speed comes from a wheel sensor and is trusted unfiltered.
    assert_in_delta 64.536, track.summary.max_speed, 0.001
  end

  test "carries per-point metrics" do
    point = track("run").points.first

    assert_equal Time.utc(2026, 3, 8, 17, 34, 54), point.recorded_at
    assert_in_delta 48.89698, point.lat, 0.00001
    assert_in_delta 2.08717, point.lon, 0.00001
    assert_in_delta 90.4, point.altitude, 0.1
    assert_equal 93, point.heart_rate
  end

  test "a record without a position yields an unlocated point" do
    result = track
    assert_equal 15_127, result.located_points.size
    assert_equal 1, result.points.size - result.located_points.size
  end

  test "reports no problems for a real activity file" do
    assert_empty track.problems
  end

  # --- Sink: the RubyFit observer protocol ----------------------------------
  # An internal seam of FitExtractor. Driven directly here so message-level
  # behaviour can be pinned without hand-building a FIT binary.

  def sink(*messages)
    FitExtractor::Sink.new.tap do |s|
      messages.each { |msg| s.on_record(msg) }
    end
  end

  test "prefers enhanced_altitude over altitude" do
    point = sink({ "timestamp" => 1_000_000, "altitude" => 234.6, "enhanced_altitude" => 234.8 })
             .to_track.points.first

    assert_in_delta 234.8, point.altitude, 0.001
  end

  test "falls back to altitude when there is no enhanced_altitude" do
    point = sink({ "timestamp" => 1_000_000, "altitude" => 234.6 }).to_track.points.first

    assert_in_delta 234.6, point.altitude, 0.001
  end

  test "leaves altitude nil when neither key is present" do
    point = sink({ "timestamp" => 1_000_000, "speed" => 10.0 }).to_track.points.first

    assert_nil point.altitude
  end

  test "prefers enhanced_speed over speed" do
    point = sink({ "timestamp" => 1_000_000, "speed" => 10.0, "enhanced_speed" => 10.5 })
             .to_track.points.first

    assert_in_delta 10.5, point.speed, 0.001
  end

  test "merges records that share a timestamp" do
    result = sink(
      { "timestamp" => 1_000_000, "heart_rate" => 120 },
      { "timestamp" => 1_000_000, "power" => 210 }
    ).to_track

    assert_equal 1, result.points.size
    assert_equal 120, result.points.first.heart_rate
    assert_equal 210, result.points.first.power
  end

  test "rejects a non-finite position" do
    point = sink({ "timestamp" => 1_000_000, "position_lat" => Float::INFINITY, "position_long" => 2.0 })
             .to_track.points.first

    assert_not point.located?
  end

  test "flags a file that is not an activity file" do
    s = FitExtractor::Sink.new
    s.on_file_id({ "type" => 1 })

    assert_equal [ :invalid_file_type ], s.to_track.problems
  end

  test "accepts an activity file without complaint" do
    s = FitExtractor::Sink.new
    s.on_file_id({ "type" => FitExtractor::ACTIVITY_FILE_TYPE })

    assert_empty s.to_track.problems
  end

  test "an empty track summarises as zero rather than nil" do
    summary = FitExtractor::Sink.new.to_track.summary

    assert_equal 0.0, summary.distance
    assert_nil summary.start_time
    assert_nil summary.max_speed
  end
end
