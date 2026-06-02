# Recomputes one activity's per-point speeds and max_speed, de-spiking GPS data.
# Non-destructive and re-runnable: speed is always re-derived from authoritative
# data (the source file or the stored GPS positions), never mutated in place.
#
# Three cases, by provenance:
#   1. Source file retained  -> re-parse it (FIT device speed / GPX Hampel).
#   2. No source, has GPS     -> recompute speed from stored positions + Hampel.
#   3. No source, no GPS       -> trust stored device speed; just refresh max.
class ActivitySpeedRefilter
  def self.call(activity) = new(activity).call

  def initialize(activity)
    @activity = activity
  end

  def call
    if activity.fit_file.attached?
      reparse_from_source
    elsif gps?
      refilter_from_positions
    else
      refresh_max_from_stored
    end
    activity.max_speed
  end

  private

  attr_reader :activity

  def reparse_from_source
    activity.activity_data_points.destroy_all
    if activity.fit_file.filename.to_s.downcase.end_with?(".gpx")
      activity.parse_gpx_file(activity.fit_file, reverse_geocode: false)
    else
      activity.parse_fit_file(activity.fit_file, reverse_geocode: false)
    end
    activity.save!(validate: false)
  end

  def refilter_from_positions
    points = activity.activity_data_points.order(:recorded_at).to_a
    recompute_position_speeds(points)
    SpeedFilter.new.filter!(points)
    points.each { |p| p.save!(validate: false) if p.changed? }
    activity.update_column(:max_speed, points.filter_map(&:speed).max)
  end

  def refresh_max_from_stored
    activity.update_column(:max_speed, activity.activity_data_points.maximum(:speed))
  end

  # Per-point speed as the great-circle distance from the previous located
  # point divided by the elapsed time.
  def recompute_position_speeds(points)
    prev = nil
    points.each do |point|
      loc = point.location
      if prev && loc
        dt = (point.recorded_at - prev.recorded_at).to_f
        distance = Haversine.distance(prev.location.y, prev.location.x, loc.y, loc.x)
        point.speed = dt.positive? ? distance / dt : nil
      else
        point.speed = nil
      end
      prev = point if loc
    end
  end

  def gps?
    activity.activity_data_points.where.not(location: nil).exists?
  end
end
