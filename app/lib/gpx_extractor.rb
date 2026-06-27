require "nokogiri"

# Parses a GPX track into an Activity + ActivityDataPoints, mirroring the
# output contract of FitExtractor. GPX has no summary block, so distance,
# elevation gain, moving time and speed are computed from the track points.
class GpxExtractor
  # Ignore elevation changes below this (meters) to filter GPS jitter.
  ELEVATION_NOISE_THRESHOLD = 3.0
  # Segments slower than this (m/s) don't count toward moving time.
  MOVING_SPEED_THRESHOLD = 0.5
  # Segments spanning a longer gap (seconds) are treated as paused recording.
  PAUSE_GAP_SECONDS = 30

  # Strava <trk><type> values -> Activity sport. Only used as a fallback when
  # the activity has no sport yet (e.g. standalone upload); the Strava importer
  # sets sport from activities.csv before calling us.
  GPX_SPORT_MAP = {
    "cycling" => :bike, "mountainbiking" => :mountain_bike_ride,
    "gravelbiking" => :gravel_ride, "ebiking" => :e_bike_ride,
    "virtualride" => :virtual_ride,
    "running" => :run, "trailrunning" => :trail_run,
    "virtualrunning" => :virtual_run, "walking" => :walk, "hiking" => :hike,
    "alpineski" => :alpine_ski, "nordicski" => :nordic_ski,
    "backcountryski" => :nordic_ski, "swimming" => :swim
  }.freeze

  def initialize(activity, reverse_geocode: true)
    @activity = activity
    @reverse_geocode = reverse_geocode
  end

  def extract(gpx_string)
    doc = Nokogiri::XML(gpx_string)
    doc.remove_namespaces!

    apply_track_metadata(doc)
    pts = parse_points(doc)
    build_data_points(pts)
  end

  private

  def apply_track_metadata(doc)
    name = doc.at_xpath("//trk/name")&.text
    @activity.name ||= name if name.present?

    type = doc.at_xpath("//trk/type")&.text
    @activity.sport ||= (GPX_SPORT_MAP[type.downcase.delete(" -_")] || :bike) if type.present?
  end

  def parse_points(doc)
    doc.xpath("//trkpt").filter_map do |node|
      lat = node["lat"]&.to_f
      lon = node["lon"]&.to_f
      time = node.at_xpath("time")&.text
      next if lat.nil? || lon.nil? || time.blank?
      next unless lat.finite? && lon.finite?

      {
        lat: lat,
        lon: lon,
        time: Time.parse(time).utc,
        ele: float(node.at_xpath("ele")&.text),
        hr: integer(node.at_xpath(".//hr")&.text),
        cad: float(node.at_xpath(".//cad")&.text),
        power: float(node.at_xpath(".//power")&.text)
      }
    end
  end

  def build_data_points(pts)
    return finalize([], 0.0, 0.0, 0.0, 0.0, nil) if pts.empty?

    prev = nil
    distance = 0.0
    moving_seconds = 0.0
    elevation_gain = 0.0
    elevation_ref = nil
    data_points = []
    coords = []

    pts.each do |pt|
      dp = @activity.activity_data_points.build(recorded_at: pt[:time])
      dp.altitude = pt[:ele] if pt[:ele]
      dp.heart_rate = pt[:hr] if pt[:hr]
      dp.cadence = pt[:cad] if pt[:cad]
      dp.power = pt[:power] if pt[:power]
      dp.location = "SRID=4326;POINT(#{pt[:lon]} #{pt[:lat]})"
      data_points << dp
      coords << "#{pt[:lon]} #{pt[:lat]}"

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
          dp.speed = speed
          moving_seconds += dt if speed >= MOVING_SPEED_THRESHOLD && dt <= PAUSE_GAP_SECONDS
        end
      end

      prev = pt
    end

    # GPX speed is derived from GPS positions and prone to spikes, so run it
    # through the Hampel filter and derive max_speed from what survives.
    max_speed = SpeedFilter.new.filter!(data_points)

    @activity.start_time = pts.first[:time]
    @activity.end_time = pts.last[:time]
    finalize(coords, distance, elevation_gain, moving_seconds, max_speed, pts.first)
  end

  def finalize(coords, distance, elevation_gain, moving_seconds, max_speed, first_point)
    @activity.distance = distance.round(1)
    @activity.total_elevation_gain = elevation_gain.round(1)
    @activity.max_speed = max_speed if max_speed&.positive?
    @activity.active_time = ActiveSupport::Duration.build(moving_seconds.round).iso8601
    # A LineString needs at least two vertices; a single-point recording (e.g. a
    # native recording stopped almost immediately, or one with a single GPS fix)
    # legitimately has no path — leave it nil rather than build an invalid geometry.
    @activity.path = "SRID=4326;LINESTRING(#{coords.join(', ')})" if coords.size >= 2

    if @reverse_geocode && first_point
      @activity.location ||= NominatimClient.new.reverse_geocode(first_point[:lat], first_point[:lon])
    end
    @activity.location ||= "Unknown"
  end

  def float(str)
    Float(str, exception: false) if str
  end

  def integer(str)
    Integer(str, exception: false) if str
  end
end
