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
    best(span, -1)
  end

  def maximum(span)
    best(span, 1)
  end

  # Every stretch spanning `span`, one per starting sample, in axis order.
  # Normalized power averages over all of them rather than keeping the best.
  def each_stretch(span)
    return enum_for(:each_stretch, span) unless block_given?

    each_window(span) { |i, j, value| yield Stretch.new(start_index: i, end_index: j, value:) }
  end

  private

  attr_reader :axis, :measure

  def best(span, sign)
    best_i = best_j = best_value = nil
    each_window(span) do |i, j, value|
      next unless best_value.nil? || sign * value > sign * best_value

      best_i, best_j, best_value = i, j, value
    end
    Stretch.new(start_index: best_i, end_index: best_j, value: best_value) if best_value
  end

  def each_window(span)
    return if span <= 0 || axis.empty? || axis.last - axis.first < span

    j = 0
    axis.each_index do |i|
      target = axis[i] + span
      j = i if j < i
      j += 1 while j < axis.size && axis[j] < target
      break if j == axis.size

      yield i, j, measure_at(target, j) - measure[i]
    end
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
