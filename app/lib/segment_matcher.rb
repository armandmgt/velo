# Finds every pass over a segment within an activity's located points (see
# CONTEXT.md). Knows nothing about ActiveRecord: the segment is a list of
# [lat, lon] vertices, the track anything responding to `recorded_at`, `lat` and
# `lon`, in track order.
#
# A pass reaches the segment's start, then its end, and visits every segment
# vertex in order on the way, so a reverse ride or a parallel road never counts.
# Efforts are timed on the wall clock between the matched points, like best
# efforts. Indices refer to the given points.
class SegmentMatcher
  START_END_TOLERANCE = 25.0
  CORRIDOR_TOLERANCE = 50.0
  METERS_PER_DEGREE = 111_320.0

  Effort = Data.define(:start_index, :end_index, :elapsed_seconds)

  def initialize(segment_points, track_points)
    @segment = segment_points
    @track   = track_points
  end

  def call
    return [] if segment.size < 2 || track.size < 2

    starts = approaches(segment.first)
    ends   = approaches(segment.last)
    efforts = []
    starts.each_with_index do |start, i|
      next if efforts.any? && start <= efforts.last.end_index

      # A later return to the start restarts the clock, so a detour back to
      # the start line never inflates the effort.
      limit = starts[i + 1] || track.size
      finish = ends.find { |e| e > start && e < limit && follows_segment?(start, e) } or next
      efforts << Effort.new(start_index: start, end_index: finish,
                            elapsed_seconds: (track[finish].recorded_at - track[start].recorded_at).to_f)
    end
    efforts
  end

  private

  attr_reader :segment, :track

  # The nearest track point of each run of points within tolerance of `target`.
  def approaches((lat, lon))
    near = track.each_index.select { |i| distance(track[i], lat, lon) <= START_END_TOLERANCE }
    near.slice_when { |a, b| b != a + 1 }.map { |run| run.min_by { |i| distance(track[i], lat, lon) } }
  end

  def follows_segment?(from, to)
    cursor = from
    segment.each do |lat, lon|
      cursor += 1 while cursor < to && distance_to_hop(cursor, lat, lon) > CORRIDOR_TOLERANCE
      return false if cursor >= to && distance(track[to], lat, lon) > CORRIDOR_TOLERANCE
    end
    true
  end

  def distance(point, lat, lon)
    Haversine.distance(point.lat, point.lon, lat, lon)
  end

  # Distance from a vertex to the track between point `i` and `i + 1`, on an
  # equirectangular projection — accurate to well under a metre at this scale.
  def distance_to_hop(i, lat, lon)
    a, b = track[i], track[i + 1]
    scale = Math.cos(lat * Math::PI / 180) * METERS_PER_DEGREE
    ax, ay = (a.lon - lon) * scale, (a.lat - lat) * METERS_PER_DEGREE
    bx, by = (b.lon - lon) * scale, (b.lat - lat) * METERS_PER_DEGREE
    dx, dy = bx - ax, by - ay
    length_squared = (dx * dx) + (dy * dy)
    t = length_squared.zero? ? 0.0 : (-((ax * dx) + (ay * dy)) / length_squared).clamp(0.0, 1.0)
    Math.hypot(ax + (t * dx), ay + (t * dy))
  end
end
