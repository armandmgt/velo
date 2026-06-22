class Activity < ApplicationRecord
  include ActivityCharts
  include ActivityMetrics
  include ActivityHeartRateZones

  belongs_to :user
  has_many :activity_data_points, dependent: :destroy

  has_one_attached :fit_file

  enum :sport, %i[
    bike mountain_bike_ride gravel_ride virtual_ride e_bike_ride
    run trail_run virtual_run walk
    hike alpine_ski nordic_ski swim workout
  ].index_by(&:itself)

  enum :visibility, %i[private shareable public].index_by(&:itself), prefix: true

  SPORT_CATEGORY = {
    bike: :cycling, mountain_bike_ride: :cycling, gravel_ride: :cycling,
    virtual_ride: :cycling, e_bike_ride: :cycling,
    run: :running, trail_run: :running, virtual_run: :running, walk: :running,
    hike: :other, alpine_ski: :other, nordic_ski: :other, swim: :other, workout: :other
  }.freeze

  validates :name, :sport, :start_time, :end_time, presence: true

  scope :awaiting_name, -> { where(name_pending: true) }

  def path_geojson
    return unless path
    {
      type: "Feature",
      geometry: {
        type: "LineString",
        properties: {},
        coordinates: path.points.map do |point|
          [ point.x, point.y ]
        end
      }
    }.to_json
  end

  def parse_fit_file(fit_file, reverse_geocode: true)
    str = fit_file.try(:read) || fit_file.download
    extractor = FitExtractor.new(self, reverse_geocode: reverse_geocode)
    RubyFit::Parser.new(extractor).parse(str)
    extractor.finalize
  end

  def parse_gpx_file(gpx_file, reverse_geocode: true)
    str = gpx_file.try(:read) || gpx_file.download
    GpxExtractor.new(self, reverse_geocode: reverse_geocode).extract(str)
  end

  def active_time_duration
    ActiveSupport::Duration.parse(active_time)
  end

  def duration
    ActiveSupport::Duration.build((end_time - start_time).to_i)
  end

  def sport_category
    SPORT_CATEGORY.fetch(sport.to_sym)
  end

  def sport_icon_name
    { cycling: "bike", running: "sport-shoe", other: "zap" }.fetch(sport_category)
  end

  def shareable_link?
    visibility_shareable? || visibility_public?
  end
end
