require "test_helper"

class SegmentMatcherTest < ActiveSupport::TestCase
  STEP = 0.0001 # ~11 m of latitude
  LON = 5.7
  OFFSET_150M = 150 / (111_320.0 * Math.cos(45.1 * Math::PI / 180))

  # A northbound segment of ~550 m, from step 10 to step 60.
  SEGMENT = (10..60).step(5).map { |i| [ 45.1 + i * STEP, LON ] }

  def points(steps, lon: ->(_) { LON })
    start = Time.zone.parse("2026-05-01 09:00:00")
    steps.each_with_index.map do |step, second|
      Track::Point.new(recorded_at: start + second.seconds, lat: 45.1 + step * STEP, lon: lon.call(step))
    end
  end

  test "a track riding start to end matches with its wall-clock time" do
    efforts = SegmentMatcher.new(SEGMENT, points((0..70).to_a)).call

    assert_equal 1, efforts.size
    assert_equal [ 10, 60, 50.0 ], efforts.first.to_h.values_at(:start_index, :end_index, :elapsed_seconds)
  end

  test "the same track reversed does not match" do
    assert_empty SegmentMatcher.new(SEGMENT, points((0..70).to_a.reverse)).call
  end

  test "a parallel road 150 m away between start and end does not match" do
    detour = ->(step) { step.between?(15, 55) ? LON + OFFSET_150M : LON }

    assert_empty SegmentMatcher.new(SEGMENT, points((0..70).to_a, lon: detour)).call
  end

  test "each of three repeats is its own effort" do
    lap = (0..70).to_a + (0..69).to_a.reverse
    efforts = SegmentMatcher.new(SEGMENT, points(lap * 3)).call

    assert_equal 3, efforts.size
    assert(efforts.all? { it.elapsed_seconds == 50.0 })
  end

  test "a return to the start line restarts the clock" do
    efforts = SegmentMatcher.new(SEGMENT, points((0..30).to_a + (0..29).to_a.reverse + (0..70).to_a)).call

    assert_equal 1, efforts.size
    assert_equal 50.0, efforts.first.elapsed_seconds
  end
end
