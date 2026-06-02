# Removes GPS-spike speeds with a Hampel filter (rolling median + MAD).
#
# A spike is a value inconsistent with its neighbors: a single second that jumps
# far off and snaps back. A real fast moment (a descent) lasts many seconds, so
# its neighbors are fast too. For each sample we compare it against the median of
# a local window; if it deviates by more than THRESHOLD robust standard
# deviations, it's an outlier and its speed is nulled.
#
# This is adaptive (judges each point against its own neighborhood, with no
# arbitrary global speed cap) and robust to clusters (median/MAD aren't thrown
# off by a few bad points in the window). Used for position-derived speeds (GPX
# import and the source-less cleanup path); FIT device speeds are trusted as-is.
class SpeedFilter
  # Window half-width in samples (≈1 Hz data, so ±7 s).
  WINDOW = 7
  # Reject when |speed - median| exceeds THRESHOLD * robust_sigma.
  THRESHOLD = 3.0
  # MAD -> standard-deviation equivalent for normally distributed data.
  MAD_SCALE = 1.4826
  # Floor on robust sigma (m/s) so a near-constant window can't collapse to a
  # zero threshold and let an obvious spike through. Roughly GPS speed noise.
  SIGMA_FLOOR = 0.5
  # Need at least this many neighbours to judge a point.
  MIN_NEIGHBOURS = 4

  # Nulls outlier speeds in place. Returns the max surviving speed (m/s), or nil.
  def filter!(points)
    speeds = points.map(&:speed)

    speeds.each_index do |i|
      next if speeds[i].nil?

      window = window_values(speeds, i)
      next if window.size <= MIN_NEIGHBOURS

      med = median(window)
      sigma = [ median(window.map { |s| (s - med).abs }) * MAD_SCALE, SIGMA_FLOOR ].max

      points[i].speed = nil if (speeds[i] - med).abs > THRESHOLD * sigma
    end

    points.filter_map(&:speed).max
  end

  private

  def window_values(speeds, index)
    lo = [ index - WINDOW, 0 ].max
    hi = [ index + WINDOW, speeds.size - 1 ].min
    speeds[lo..hi].compact
  end

  def median(values)
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
