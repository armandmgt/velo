class PlannedRoute < ApplicationRecord
  belongs_to :user

  ROUTABLE_SPORTS = %i[
    bike gravel_ride mountain_bike_ride e_bike_ride
    run trail_run walk hike
  ].freeze

  BROUTER_PROFILE = {
    bike:               "fastbike",
    gravel_ride:        "trekking",
    mountain_bike_ride: "mtb",
    e_bike_ride:        "trekking",
    run:                "hiking-beta",
    trail_run:          "hiking-beta",
    walk:               "hiking-beta",
    hike:               "hiking-beta"
  }.freeze

  # Waypoints ride in BRouter's GET query string (~22 chars each), so an
  # unbounded list is both a URL-length problem and a way to abuse a third party.
  MAX_WAYPOINTS = 100

  enum :sport, ROUTABLE_SPORTS.index_by(&:itself)
  enum :visibility, %i[private shareable public].index_by(&:itself), prefix: true

  validates :name, presence: true
  validates :sport, presence: true, inclusion: { in: sports.keys }
  validate  :waypoints_shape

  scope :recent, -> { order(created_at: :desc) }

  def self.brouter_profile_for(sport)
    BROUTER_PROFILE.fetch(sport.to_sym)
  end

  def sport_category
    Activity::SPORT_CATEGORY.fetch(sport.to_sym)
  end

  def sport_icon_name
    { cycling: "bike", running: "sport-shoe", other: "zap" }.fetch(sport_category)
  end

  def shareable_link?
    visibility_shareable? || visibility_public?
  end

  def path_coordinates
    return [] unless path
    path.points.map { |point| [ point.x, point.y ] }
  end

  def path_geojson
    return unless path
    {
      type: "Feature",
      geometry: {
        type: "LineString",
        properties: {},
        coordinates: path_coordinates
      }
    }.to_json
  end

  # Shape consumed by elevation_profile_controller (xMode: distance).
  # labels: cumulative distance in meters; data: elevation in meters.
  # Returns nil when BRouter didn't provide z-values for this route.
  def elevation_chart_data
    return nil if elevation_samples.blank?
    {
      labels: elevation_samples.map { |sample| sample[0] },
      data:   elevation_samples.map { |sample| sample[1] }
    }
  end

  # Serializes the route as a GPX 1.1 document with a single <trk>. <ele> is
  # emitted only for points where BRouter provided a z-value. No <time> — a
  # planned route is not a recording.
  def to_gpx
    points = path&.points || []
    elevations = elevation_samples || []

    Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.gpx(version: "1.1", creator: "Velo",
              xmlns: "http://www.topografix.com/GPX/1/1") do
        xml.trk do
          xml.name name
          xml.type sport
          xml.trkseg do
            points.each_with_index do |point, i|
              xml.trkpt(lat: point.y, lon: point.x) do
                ele = elevations[i]&.last
                xml.ele(ele) if ele
              end
            end
          end
        end
      end
    end.to_xml
  end

  private

  def waypoints_shape
    return errors.add(:waypoints, :invalid) unless waypoints.is_a?(Array)
    return errors.add(:waypoints, :too_short, count: 2) if waypoints.length < 2
    return errors.add(:waypoints, :too_long, count: MAX_WAYPOINTS) if waypoints.length > MAX_WAYPOINTS

    return if waypoints.all? do |pair|
      pair.is_a?(Array) && pair.length == 2 &&
        pair[0].is_a?(Numeric) && pair[1].is_a?(Numeric) &&
        pair[0].between?(-180, 180) && pair[1].between?(-90, 90)
    end

    errors.add(:waypoints, :invalid)
  end
end
