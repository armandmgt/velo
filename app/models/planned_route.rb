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

  enum :sport, ROUTABLE_SPORTS.index_by(&:itself)

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

  private

  def waypoints_shape
    return errors.add(:waypoints, :invalid) unless waypoints.is_a?(Array)
    return errors.add(:waypoints, :too_short, count: 2) if waypoints.length < 2

    return if waypoints.all? do |pair|
      pair.is_a?(Array) && pair.length == 2 &&
        pair[0].is_a?(Numeric) && pair[1].is_a?(Numeric) &&
        pair[0].between?(-180, 180) && pair[1].between?(-90, 90)
    end

    errors.add(:waypoints, :invalid)
  end
end
