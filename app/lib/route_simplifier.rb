# Reduces a dense GPS track to a handful of shape-preserving waypoints using
# Ramer-Douglas-Peucker.
#
# Even striding is geometry-blind: on a track that is mostly straight with a few
# hairpins it spends its whole budget on the straights, so BRouter re-routes the
# corners however it likes — which users see as "it didn't follow my track". RDP
# spends waypoints where the track actually changes direction, which is exactly
# where the router needs pinning, and keeps the first and last point by
# construction so the seeded route starts and ends where the track does.
class RouteSimplifier
  MAX_POINTS = 20
  # RDP is O(n log n) typically but degrades to O(n^2) on adversarial input.
  # Pre-sampling bounds the work; 2000 samples is ~50 m granularity on a 100 km
  # track, well below any tolerance we'd end up simplifying at.
  PRE_SAMPLE_LIMIT = 2_000
  INITIAL_TOLERANCE_METERS = 10.0
  # 10 m doubled 24 times is ~84,000 km — past Earth's circumference, so any
  # real track collapses to its endpoints long before we run out of doublings.
  MAX_TOLERANCE_DOUBLINGS = 24
  METERS_PER_DEGREE = 111_320.0

  # points: Array<[lon, lat]>. Returns a subset in the original order.
  def self.call(points, max_points: MAX_POINTS)
    new(points, max_points: max_points).call
  end

  def initialize(points, max_points: MAX_POINTS)
    @points = points
    @max_points = [ max_points, 2 ].max
  end

  def call
    return @points if @points.size <= @max_points

    points = pre_sample(@points)
    tolerance = INITIAL_TOLERANCE_METERS
    simplified = points

    MAX_TOLERANCE_DOUBLINGS.times do
      simplified = douglas_peucker(points, tolerance)
      break if simplified.size <= @max_points
      tolerance *= 2
    end

    # Degenerate input (every point identical, say) defeats any tolerance, since
    # no point is ever further than 0 m from the segment. Fall back to a stride
    # that still keeps both ends.
    simplified.size <= @max_points ? simplified : stride(simplified, @max_points)
  end

  private

  def pre_sample(points)
    points.size <= PRE_SAMPLE_LIMIT ? points : stride(points, PRE_SAMPLE_LIMIT)
  end

  # Iterative rather than recursive: a 30k-point track would otherwise recurse
  # deep enough to blow the stack.
  def douglas_peucker(points, tolerance)
    keep = Array.new(points.size, false)
    keep[0] = true
    keep[-1] = true
    pending = [ [ 0, points.size - 1 ] ]

    until pending.empty?
      first, last = pending.pop
      next if last <= first + 1

      farthest = nil
      max_distance = tolerance

      ((first + 1)...last).each do |i|
        distance = perpendicular_distance(points[i], points[first], points[last])
        if distance > max_distance
          max_distance = distance
          farthest = i
        end
      end

      next if farthest.nil?

      keep[farthest] = true
      pending.push([ first, farthest ], [ farthest, last ])
    end

    points.each_with_index.filter_map { |point, i| point if keep[i] }
  end

  # Equirectangular projection centred on the segment start — accurate to well
  # under a metre across a single simplification span, and far cheaper than
  # haversine inside the inner loop.
  def perpendicular_distance(point, segment_start, segment_end)
    scale = Math.cos(segment_start[1] * Math::PI / 180)

    px = (point[0] - segment_start[0]) * scale * METERS_PER_DEGREE
    py = (point[1] - segment_start[1]) * METERS_PER_DEGREE
    ex = (segment_end[0] - segment_start[0]) * scale * METERS_PER_DEGREE
    ey = (segment_end[1] - segment_start[1]) * METERS_PER_DEGREE

    length_squared = (ex * ex) + (ey * ey)
    return Math.sqrt((px * px) + (py * py)) if length_squared.zero?

    t = (((px * ex) + (py * ey)) / length_squared).clamp(0.0, 1.0)
    dx = px - (t * ex)
    dy = py - (t * ey)
    Math.sqrt((dx * dx) + (dy * dy))
  end

  # Unlike a plain `i % stride == 0` filter, this always ends on the final point:
  # a seeded route must not stop short of the track it came from.
  def stride(points, limit)
    step = (points.size.to_f / (limit - 1)).ceil
    kept = points.each_slice(step).map(&:first)
    kept << points.last unless kept.last == points.last
    kept
  end
end
