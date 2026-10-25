require "nokogiri"

# Reads a GPX file into a Track. GPX has no summary block, so distance,
# elevation gain, moving time and speed are computed from the track points —
# unlike FIT, which reads them off the device's session message.
#
# Also serves planned-route seeding, which needs the raw waypoints rather than a
# Track: see `gpx?`, `track_name` and `parse_points`.
class GpxExtractor
  # Ignore elevation changes below this (meters) to filter GPS jitter.
  ELEVATION_NOISE_THRESHOLD = 3.0
  # Segments slower than this (m/s) don't count toward moving time.
  MOVING_SPEED_THRESHOLD = 0.5
  # Segments spanning a longer gap (seconds) are treated as paused recording.
  PAUSE_GAP_SECONDS = 30

  # Strava <trk><type> values -> Activity sport. Only a suggestion: a rider's own
  # sport wins, which is how the Strava importer's activities.csv value survives.
  GPX_SPORT_MAP = {
    "cycling" => :bike, "mountainbiking" => :mountain_bike_ride,
    "gravelbiking" => :gravel_ride, "ebiking" => :e_bike_ride,
    "virtualride" => :virtual_ride,
    "running" => :run, "trailrunning" => :trail_run,
    "virtualrunning" => :virtual_run, "walking" => :walk, "hiking" => :hike,
    "alpineski" => :alpine_ski, "nordicski" => :nordic_ski,
    "backcountryski" => :nordic_ski, "swimming" => :swim
  }.freeze

  def initialize(gpx_string)
    # NONET is explicit so a crafted external entity can't make the server fetch
    # a URL while parsing an upload.
    @doc = Nokogiri::XML(gpx_string, &:nonet)
    @doc.remove_namespaces!
  end

  def extract
    # Track points carry timestamps by definition, and recorded_at is NOT NULL.
    # A route-style GPX (Komoot, RideWithGPS, our own PlannedRoute#to_gpx) has no
    # <time> at all and degrades to an empty Track — which fails Activity's
    # start_time validation as a 422, rather than raising.
    # A point per second is the most an activity stores, and a phone can hand back
    # a stale fix that repeats an earlier second; the first one recorded wins.
    build(parse_points.select { |pt| pt[:time] }.uniq { |pt| pt[:time] })
  end

  # Nokogiri recovers from malformed input rather than raising, so an arbitrary
  # upload still yields a document — one with no root. That's the signal callers
  # need to reject a file that merely ends in .gpx.
  def gpx?
    @doc.root&.name == "gpx"
  end

  def track_name
    @doc.at_xpath("//trk/name")&.text.presence || @doc.at_xpath("//rte/name")&.text.presence
  end

  # Permissive on purpose: the route planner seeds waypoints from files that
  # carry no timestamps, so points with no usable <time> come back with nil.
  def parse_points
    point_nodes.filter_map do |node|
      lat = node["lat"]&.to_f
      lon = node["lon"]&.to_f
      next if lat.nil? || lon.nil?
      next unless lat.finite? && lon.finite?

      {
        lat: lat,
        lon: lon,
        time: parse_time(node.at_xpath("time")&.text),
        ele: float(node.at_xpath("ele")&.text),
        hr: integer(node.at_xpath(".//hr")&.text),
        cad: float(node.at_xpath(".//cad")&.text),
        power: float(node.at_xpath(".//power")&.text)
      }
    end
  end

  private

  # <trk> is the recording form and wins when present. <rte> is the planning
  # form most route builders export; fall back to it so those files still seed a
  # route. <wpt> is deliberately ignored — those are unordered POIs, not a path.
  def point_nodes
    nodes = @doc.xpath("//trkpt")
    nodes.empty? ? @doc.xpath("//rtept") : nodes
  end

  # A garbage <time> must not take down the whole parse; the planner doesn't
  # need timestamps and #extract drops the point anyway.
  def parse_time(str)
    return nil if str.blank?
    Time.parse(str).utc
  rescue ArgumentError
    nil
  end

  def suggested_sport
    type = @doc.at_xpath("//trk/type")&.text
    return nil if type.blank?

    GPX_SPORT_MAP[type.downcase.delete(" -_")] || :bike
  end

  def build(pts)
    return empty_track if pts.empty?

    prev = nil
    distance = 0.0
    moving_seconds = 0.0
    elevation_gain = 0.0
    elevation_ref = nil
    points = []

    pts.each do |pt|
      point = Track::Point.new(
        recorded_at: pt[:time], lat: pt[:lat], lon: pt[:lon],
        altitude: pt[:ele], heart_rate: pt[:hr], cadence: pt[:cad], power: pt[:power]
      )
      points << point

      if pt[:ele]
        elevation_ref ||= pt[:ele]
        diff = pt[:ele] - elevation_ref
        if diff > ELEVATION_NOISE_THRESHOLD
          elevation_gain += diff
          elevation_ref = pt[:ele]
        elsif diff.negative?
          elevation_ref = pt[:ele]
        end
      end

      if prev
        seg = Haversine.distance(prev[:lat], prev[:lon], pt[:lat], pt[:lon])
        dt = pt[:time] - prev[:time]
        distance += seg

        if dt.positive?
          speed = seg / dt
          point.speed = speed
          moving_seconds += dt if speed >= MOVING_SPEED_THRESHOLD && dt <= PAUSE_GAP_SECONDS
        end
      end

      prev = pt
    end

    # GPX speed is derived from GPS positions and prone to spikes, so run it
    # through the Hampel filter and derive max_speed from what survives.
    max_speed = SpeedFilter.new.filter!(points)

    Track.new(
      points: points,
      summary: Track::Summary.new(
        distance: distance.round(1),
        elevation_gain: elevation_gain.round(1),
        moving_seconds: moving_seconds.round,
        max_speed: (max_speed if max_speed&.positive?),
        start_time: pts.first[:time],
        end_time: pts.last[:time]
      ),
      suggested_name: track_name,
      suggested_sport: suggested_sport
    )
  end

  def empty_track
    Track.new(
      points: [],
      summary: Track::Summary.empty,
      suggested_name: track_name,
      suggested_sport: suggested_sport
    )
  end

  def float(str)
    Float(str, exception: false) if str
  end

  def integer(str)
    Integer(str, exception: false) if str
  end
end
