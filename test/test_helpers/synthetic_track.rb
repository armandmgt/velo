# Builds a straight track along the equator from legs of steady movement and
# stops, so tests can state exact distances and times.
class SyntheticTrack
  METERS_PER_DEGREE = Haversine::EARTH_RADIUS_M * Math::PI / 180

  attr_reader :points

  def initialize(start: Time.utc(2026, 6, 1, 8), power: nil)
    @time   = start
    @power  = power
    @meters = 0.0
    @points = []
    sample
  end

  # Moves `meters` at `speed` m/s, sampling every `every` metres, each sample
  # carrying `power` watts when given.
  def move(meters, speed:, every: speed, power: nil)
    @power = power
    remaining = meters.to_f
    while remaining > 1e-9
      hop = [ every, remaining ].min
      @meters += hop
      @time += hop / speed
      remaining -= hop
      sample
    end
    self
  end

  # Stays put for `seconds`, still sampling every second.
  def stop(seconds, power: nil)
    @power = power
    seconds.times do
      @time += 1
      sample
    end
    self
  end

  def to_gpx(type: "running")
    trkpts = points.map do |point|
      extensions = "<extensions><power>#{point.power}</power></extensions>" if point.power
      %(<trkpt lat="#{point.lat}" lon="#{point.lon}"><time>#{point.recorded_at.utc.iso8601(3)}</time>#{extensions}</trkpt>)
    end
    %(<?xml version="1.0"?><gpx><trk><type>#{type}</type><trkseg>#{trkpts.join}</trkseg></trk></gpx>)
  end

  private

  def sample
    @points << Track::Point.new(recorded_at: @time, lat: 0.0, lon: @meters / METERS_PER_DEGREE, power: @power)
  end
end
