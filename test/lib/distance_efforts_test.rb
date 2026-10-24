require "test_helper"
require_relative "../test_helpers/synthetic_track"

class DistanceEffortsTest < ActiveSupport::TestCase
  RUNNING = BestEffort::DISTANCES[:running]
  TEN_KMH = 10 / 3.6

  def efforts(track, distances: RUNNING, max_speed: 12.5)
    DistanceEfforts.new(track.points, distances:, max_speed:).call.index_by(&:key)
  end

  test "efforts run on the wall clock, stops included" do
    track = SyntheticTrack.new.move(6_000, speed: TEN_KMH).stop(300).move(6_000, speed: TEN_KMH)

    result = efforts(track)

    assert_in_delta 360.0, result["1k"].elapsed_seconds, 0.01, "1 km avoids the stop: 6:00"
    assert_in_delta 3_600.0 + 300, result["10k"].elapsed_seconds, 0.01, "10 km can't avoid the 5-minute stop"
    assert_nil result["15k"], "the track doesn't cover 15 km"
  end

  test "interpolates the far end between sparse points" do
    track = SyntheticTrack.new.move(3_000, speed: 4.0, every: 40)

    result = efforts(track)

    assert_in_delta 250.0, result["1k"].elapsed_seconds, 1.0
    assert_in_delta BestEffort::MILE / 4.0, result["1_mile"].elapsed_seconds, 1.0
  end

  test "offsets point at the stretch's first and last points" do
    track = SyntheticTrack.new.move(1_000, speed: 2.0, every: 100).move(1_000, speed: 5.0, every: 100)

    effort = efforts(track)["1k"]

    assert_equal 10, effort.start_index
    assert_equal 20, effort.end_index
  end

  test "a GPS glitch covers no ground" do
    track = SyntheticTrack.new.move(1_500, speed: 3.0)
    track.points << Track::Point.new(recorded_at: track.points.last.recorded_at + 1,
                                     lat: 0.0, lon: track.points.last.lon + 0.02)

    effort = efforts(track)["1k"]

    assert_operator 1_000 / effort.elapsed_seconds, :<=, 12.5
    assert_in_delta 1_000 / 3.0, effort.elapsed_seconds, 1.0
  end

  test "no efforts without timestamps or distances" do
    track = SyntheticTrack.new.move(2_000, speed: 3.0)
    track.points.first.recorded_at = nil

    assert_empty efforts(track)
    assert_empty efforts(SyntheticTrack.new.move(2_000, speed: 3.0), distances: {})
  end
end
