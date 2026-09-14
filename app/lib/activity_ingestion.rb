# Turns a Source file into a populated, unsaved Activity. See CONTEXT.md.
#
# Owns format dispatch, extraction and the normalisation defaults that every
# origin needs. Deliberately does NOT save, deduplicate or attach the source —
# see docs/adr/0004-ingestion-stops-before-persistence.md.
#
# Time fallbacks are opt-in because the origins genuinely differ: a rider's
# upload of a timeless GPX must still fail validation as a 422, while a bulk
# import would rather keep the activity and fill the gap.
class ActivityIngestion
  def self.call(...)
    new(...).call
  end

  def initialize(activity, source, filename:, reverse_geocode: true,
                 fallback_start_time: nil, fallback_end_time: nil)
    @activity            = activity
    @source              = source
    @filename            = filename
    @reverse_geocode     = reverse_geocode
    @fallback_start_time = fallback_start_time
    @fallback_end_time   = fallback_end_time
  end

  def call
    apply(extract)
    activity
  end

  private

  attr_reader :activity, :source, :filename, :reverse_geocode

  def extract
    gpx? ? GpxExtractor.new(bytes).extract : FitExtractor.new(bytes).extract
  end

  def gpx?
    filename.to_s.downcase.end_with?(".gpx")
  end

  def bytes
    source.try(:read) || source.download
  end

  def apply(track)
    apply_hints(track)
    apply_summary(track.summary)
    build_data_points(track)
    apply_path(track)
    apply_location(track)
    apply_fallbacks
    track.problems.each { |problem| activity.errors.add(:source_file, problem) }
  end

  # A rider's own name and sport win over the file's — which is how the Strava
  # importer's activities.csv values survive a GPX that disagrees.
  def apply_hints(track)
    activity.name  ||= track.suggested_name if track.suggested_name.present?
    activity.sport ||= track.suggested_sport if track.suggested_sport
  end

  def apply_summary(summary)
    activity.start_time = summary.start_time if summary.start_time
    activity.end_time   = summary.end_time   if summary.end_time
    activity.distance   = summary.distance
    activity.total_elevation_gain = summary.elevation_gain
    activity.max_speed  = summary.max_speed if summary.max_speed&.positive?
    activity.active_time = ActiveSupport::Duration.build(summary.moving_seconds.to_i).iso8601
  end

  def build_data_points(track)
    track.points.each do |point|
      activity.activity_data_points.build(
        recorded_at: point.recorded_at,
        altitude:    point.altitude,
        heart_rate:  point.heart_rate,
        cadence:     point.cadence,
        power:       point.power,
        speed:       point.speed,
        location:    ("SRID=4326;POINT(#{point.lon} #{point.lat})" if point.located?)
      )
    end
  end

  # A LineString needs at least two vertices; a single-fix recording (a native
  # recording stopped almost immediately, say) legitimately has no path — leave
  # it nil rather than build an invalid geometry.
  def apply_path(track)
    coords = track.located_points.map { |point| "#{point.lon} #{point.lat}" }
    return if coords.size < 2

    activity.path = "SRID=4326;LINESTRING(#{coords.join(', ')})"
  end

  def apply_location(track)
    if reverse_geocode && (fix = track.first_fix)
      activity.location ||= NominatimClient.new.reverse_geocode(fix.lat, fix.lon)
    end
    activity.location ||= "Unknown"
  end

  def apply_fallbacks
    return unless @fallback_start_time || @fallback_end_time

    activity.start_time ||= @fallback_start_time
    activity.end_time   ||= @fallback_end_time || activity.start_time
  end
end
