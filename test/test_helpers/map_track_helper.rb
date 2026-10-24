# A straight northbound track, one data point per STEP_DEGREES of latitude
# (~44 m), so tests can reason about distances along it by index.
module MapTrackHelper
  STEP_DEGREES = 0.0004
  STEP_METRES = 44.45
  START_LAT = 45.1
  LNG = 5.7

  def track_lat(index)
    (START_LAT + index * STEP_DEGREES).round(6)
  end

  def create_track(activity, points: 61)
    activity.activity_data_points.delete_all
    start = Time.zone.parse("2026-05-01 09:00:00")
    rows = Array.new(points) do |i|
      { activity_id: activity.id, recorded_at: start + i.seconds, altitude: 200 + i, speed: 5.0,
        location: "SRID=4326;POINT(#{LNG} #{track_lat(i)})", created_at: start, updated_at: start }
    end
    ActivityDataPoint.insert_all!(rows)
    activity.update!(path: "SRID=4326;LINESTRING(#{Array.new(points) { |i| "#{LNG} #{track_lat(i)}" }.join(', ')})")
    activity
  end
end

ActiveSupport.on_load(:active_support_test_case) { include MapTrackHelper }
