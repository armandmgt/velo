# The best contiguous stretch of an ordered series spanning a fixed amount of
# its axis — the core of a best effort (see CONTEXT.md).
#
# The series is two running totals over the same samples: an `axis` that the
# span is measured along, and a `measure` whose change over the stretch is
# what's being optimised. Both are cumulative and the axis never decreases.
#
#   distance best effort:  axis = metres covered,  measure = seconds elapsed → minimum
#   power best effort:     axis = seconds elapsed, measure = joules produced → maximum
#
# A stretch starts on a sample and ends exactly `span` further along the axis,
# interpolating the measure inside the sample pair that straddles that point, so
# sparse samples don't overcharge the effort for the overshoot.
class BestStretch
  # `end_index` is the first sample at or past the interpolated end.
  Stretch = Data.define(:start_index, :end_index, :value)

  def initialize(axis:, measure:)
    raise ArgumentError, "axis and measure differ in length" unless axis.size == measure.size

    @axis    = axis
    @measure = measure
  end

  def minimum(span)
    best(span) { |candidate, current| candidate < current.value }
  end

  def maximum(span)
    best(span) { |candidate, current| candidate > current.value }
  end

  private

  attr_reader :axis, :measure

  def best(span)
    return if span <= 0 || axis.empty? || axis.last - axis.first < span

    best = nil
    j = 0
    axis.each_index do |i|
      target = axis[i] + span
      j = i if j < i
      j += 1 while j < axis.size && axis[j] < target
      break if j == axis.size

      value = measure_at(target, j) - measure[i]
      best = Stretch.new(start_index: i, end_index: j, value: value) if best.nil? || yield(value, best)
    end
    best
  end

  # Index j is the first sample with axis >= target, and j > start, so the
  # previous sample sits strictly before target.
  def measure_at(target, j)
    return measure[j] if axis[j] == target

    a0 = axis[j - 1]
    m0 = measure[j - 1]
    m0 + (measure[j] - m0) * (target - a0).fdiv(axis[j] - a0)
  end
end
