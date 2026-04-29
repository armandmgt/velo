class Activity < ApplicationRecord
  include ActivityCharts

  belongs_to :user
  has_many :activity_data_points, dependent: :destroy

  has_one_attached :fit_file

  enum :sport, %i[
    bike
    run
  ].index_by(&:itself)

  validates :name, :sport, :start_time, :end_time, presence: true

  def path_geojson
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

  def active_time_duration
    ActiveSupport::Duration.parse(active_time)
  end

  def duration
    ActiveSupport::Duration.build((end_time - start_time).to_i)
  end

  def sport_icon_name
    {
      "bike" => "bike",
      "run" => "sport-shoe"
    }.fetch(sport)
  end
end
