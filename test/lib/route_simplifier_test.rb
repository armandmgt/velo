require "test_helper"

class RouteSimplifierTest < ActiveSupport::TestCase
  # Roughly 11 m per 0.0001 degree of latitude at this scale.
  BASE_LAT = 48.8566
  BASE_LON = 2.3522

  def straight_line(count, step: 0.0005)
    (0...count).map { |i| [ BASE_LON + (i * step), BASE_LAT ] }
  end

  def winding_track(count)
    (0...count).map { |i| [ BASE_LON + (i * 0.0005), BASE_LAT + (Math.sin(i / 20.0) * 0.01) ] }
  end

  def meters_between(a, b)
    dx = (a[0] - b[0]) * Math.cos(b[1] * Math::PI / 180) * 111_320.0
    dy = (a[1] - b[1]) * 111_320.0
    Math.sqrt((dx * dx) + (dy * dy))
  end

  test "returns short input untouched" do
    points = [ [ 2.35, 48.85 ], [ 2.36, 48.86 ], [ 2.37, 48.87 ] ]
    assert_equal points, RouteSimplifier.call(points)
  end

  test "handles a two-point input" do
    points = [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ]
    assert_equal points, RouteSimplifier.call(points)
  end

  test "never exceeds the cap" do
    assert_operator RouteSimplifier.call(winding_track(1_000)).size, :<=, RouteSimplifier::MAX_POINTS
  end

  test "honours an explicit cap of two" do
    assert_equal 2, RouteSimplifier.call(winding_track(1_000), max_points: 2).size
  end

  # The old stride kept the last point only when (size - 1) % stride == 0, so a
  # seeded route could stop short of the track it came from.
  test "always keeps the first and last point" do
    points = winding_track(500)
    simplified = RouteSimplifier.call(points)

    assert_equal points.first, simplified.first
    assert_equal points.last, simplified.last
  end

  test "collapses a straight line to its endpoints" do
    assert_equal 2, RouteSimplifier.call(straight_line(50)).size
  end

  # The point of RDP over striding: budget goes where the track changes
  # direction, not evenly along it.
  test "spends waypoints on corners rather than straights" do
    leg_north = (0...150).map { |i| [ BASE_LON, BASE_LAT + (i * 0.0001) ] }
    corner    = leg_north.last
    leg_east  = (1...150).map { |i| [ BASE_LON + (i * 0.00015), corner[1] ] }
    points    = leg_north + leg_east

    simplified = RouteSimplifier.call(points)

    assert_operator simplified.size, :<=, RouteSimplifier::MAX_POINTS
    assert simplified.any? { |point| meters_between(point, corner) < 20 },
           "expected a waypoint within 20 m of the corner, got #{simplified.inspect}"
  end

  test "preserves a deviation an even stride would skip" do
    points = straight_line(200, step: 0.0002)
    apex = [ points[137][0], BASE_LAT + 0.004 ]
    points[137] = apex

    assert_includes RouteSimplifier.call(points), apex
  end

  # Every point identical defeats any tolerance — no point is ever further than
  # 0 m from the segment — so the loop must terminate on its own.
  test "survives degenerate input" do
    points = Array.new(100) { [ BASE_LON, BASE_LAT ] }
    simplified = RouteSimplifier.call(points)

    assert_operator simplified.size, :<=, RouteSimplifier::MAX_POINTS
    assert_operator simplified.size, :>=, 2
  end

  # Pre-sampling is what keeps this from being O(n^2) and from recursing deep
  # enough to blow the stack.
  test "handles a track far larger than the pre-sample limit" do
    points = winding_track(30_000)
    simplified = RouteSimplifier.call(points)

    assert_operator simplified.size, :<=, RouteSimplifier::MAX_POINTS
    assert_equal points.first, simplified.first
    assert_equal points.last, simplified.last
  end

  test "preserves the original order" do
    points = winding_track(500)
    simplified = RouteSimplifier.call(points)

    indices = simplified.map { |point| points.index(point) }
    assert_equal indices.sort, indices
  end
end
