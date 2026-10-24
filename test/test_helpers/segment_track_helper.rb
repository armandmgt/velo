# Tracks and segments along the equator, placed by metres east of the origin, so
# segment tests can state where a pass starts and ends and how long it took.
module SegmentTrackHelper
  METERS_PER_DEGREE = Haversine::EARTH_RADIUS_M * Math::PI / 180

  # One Track::Point per entry of `meters`, `every` seconds apart; `north` gives
  # the offset (metres) of each position from the equator.
  def points_at(meters, start: Time.utc(2026, 6, 1, 8), every: 1, north: ->(_) { 0 })
    meters.each_with_index.map do |m, i|
      Track::Point.new(recorded_at: start + (i * every), lat: north.call(m) / METERS_PER_DEGREE,
                       lon: m / METERS_PER_DEGREE, altitude: 100 + m / 20.0)
    end
  end

  # Positions every 10 m from `from` to `to` metres (either direction).
  def ride(from, to)
    from <= to ? from.step(to, 10).to_a : from.step(to, -10).to_a
  end

  def gpx_for(points)
    trkpts = points.map do |point|
      %(<trkpt lat="#{point.lat}" lon="#{point.lon}"><ele>#{point.altitude}</ele>) +
        %(<time>#{point.recorded_at.utc.iso8601(3)}</time></trkpt>)
    end
    %(<?xml version="1.0"?><gpx><trk><trkseg>#{trkpts.join}</trkseg></trk></gpx>)
  end

  def ingest_points(user, points, sport: :run, visibility: :public, name: "Sortie")
    activity = user.activities.build(name:, sport:, visibility:)
    ActivityIngestion.call(activity, StringIO.new(gpx_for(points)), filename: "track.gpx", reverse_geocode: false)
    activity.save!
    activity
  end

  def create_segment(from:, to:, category: "running", name: "Segment #{from}-#{to}", user: users(:one))
    segment = Segment.new(name:, sport_category: category, user:)
    segment.trace(points_at(ride(from, to)).map { [ it.lat, it.lon, it.altitude ] })
    segment.save!
    segment
  end
end

ActiveSupport.on_load(:active_support_test_case) { include SegmentTrackHelper }
