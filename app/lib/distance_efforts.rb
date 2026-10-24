# An activity's best efforts over standard distances, computed from its located
# points (see CONTEXT.md). Knows nothing about ActiveRecord: it takes anything
# responding to `recorded_at`, `lat` and `lon`, in track order.
#
# Efforts are timed on the wall clock, stops included, as in a race. Indices
# refer to the given points, which ingestion also turns into the path vertices.
#
# A hop between two fixes faster than `max_speed` is a GPS glitch, not ground
# covered: it adds time but no distance, so no effort can imply an impossible
# speed for the sport.
class DistanceEfforts
  Effort = Data.define(:key, :meters, :elapsed_seconds, :start_index, :end_index)

  def initialize(points, distances:, max_speed:)
    @points    = points
    @distances = distances
    @max_speed = max_speed
  end

  def call
    return [] if distances.empty? || !(series = cumulative_series)

    stretch = BestStretch.new(axis: series[:meters], measure: series[:seconds])
    distances.filter_map do |key, meters|
      best = stretch.minimum(meters) or next

      Effort.new(key:, meters:, elapsed_seconds: best.value,
                 start_index: best.start_index, end_index: best.end_index)
    end
  end

  private

  attr_reader :points, :distances, :max_speed

  def cumulative_series
    return if points.size < 2 || points.any? { |point| point.recorded_at.nil? }

    origin  = points.first.recorded_at
    meters  = [ 0.0 ]
    seconds = [ 0.0 ]
    points.each_cons(2) do |from, to|
      dt = to.recorded_at - from.recorded_at
      return if dt.negative?

      hop = Haversine.distance(from.lat, from.lon, to.lat, to.lon)
      meters  << meters.last + (dt.positive? && hop / dt <= max_speed ? hop : 0.0)
      seconds << (to.recorded_at - origin).to_f
    end
    { meters:, seconds: }
  end
end
