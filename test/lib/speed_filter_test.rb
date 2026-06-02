require "test_helper"

class SpeedFilterTest < ActiveSupport::TestCase
  # Lightweight stand-in for ActivityDataPoint: responds to #speed / #speed=.
  Sample = Struct.new(:speed)

  def points(speeds) = speeds.map { |s| Sample.new(s) }

  test "nulls an isolated spike against a steady background" do
    speeds = Array.new(8, 6.0) + [ 48.0 ] + Array.new(8, 6.0) # 48 m/s spike
    pts = points(speeds)
    max = SpeedFilter.new.filter!(pts)

    assert_nil pts[8].speed
    assert_in_delta 6.0, max, 0.001
  end

  test "nulls a spike well below any fixed cap (it's still a local outlier)" do
    # 18 m/s (65 km/h) — plausible on a bike in absolute terms, but a spike here.
    speeds = Array.new(8, 5.0) + [ 18.0 ] + Array.new(8, 5.0)
    pts = points(speeds)
    SpeedFilter.new.filter!(pts)

    assert_nil pts[8].speed
  end

  test "keeps a sustained fast stretch (a real descent)" do
    # A descent that stays fast for many samples is not an outlier — every fast
    # point must survive so max_speed reflects the real peak.
    speeds = Array.new(6, 6.0) + Array.new(10, 18.0) + Array.new(6, 6.0)
    pts = points(speeds)
    max = SpeedFilter.new.filter!(pts)

    assert_equal Array.new(10, 18.0), pts[6..15].map(&:speed), "no fast point should be nulled"
    assert_in_delta 18.0, max, 0.001
  end

  test "leaves gently varying data untouched" do
    speeds = [ 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 9.0, 8.0, 7.0, 6.0, 5.0 ]
    pts = points(speeds)
    max = SpeedFilter.new.filter!(pts)

    assert_equal speeds, pts.map(&:speed)
    assert_in_delta 10.0, max, 0.001
  end

  test "removes multiple spikes in the same window" do
    speeds = Array.new(6, 6.0) + [ 40.0, 6.0, 45.0 ] + Array.new(6, 6.0)
    pts = points(speeds)
    max = SpeedFilter.new.filter!(pts)

    assert_nil pts[6].speed
    assert_nil pts[8].speed
    assert_in_delta 6.0, max, 0.001
  end

  test "skips nil speeds and returns nil when nothing remains" do
    pts = points(Array.new(8, nil) + [ 48.0 ] + Array.new(8, nil))
    max = SpeedFilter.new.filter!(pts)

    # The lone value has too few neighbours to judge, so it's left as-is here;
    # the point is that nils don't raise and an empty result returns nil.
    assert_equal 48.0, max
    assert_nil SpeedFilter.new.filter!(points([])), "empty input returns nil"
  end
end
