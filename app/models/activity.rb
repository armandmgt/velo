class Activity < ApplicationRecord
  belongs_to :user

  has_one_attached :fit_file

  enum :sport, %i[
    bike
    run
  ].index_by(&:itself)

  validates :name, :sport, :start_time, :end_time, :location, :active_time, presence: true

  class Positions
    attr_reader :latitude, :longitude

    def self.load(payload)
      return nil if payload.nil?

      data = JSON.parse(payload)
      new(data["latitude"], data["longitude"])
    end

    def self.dump(positions)
      JSON.generate(
        "latitude" => positions.latitude,
        "longitude" => positions.longitude,
      )
    end

    def initialize(latitude, longitude)
      # Always store arrays for consistency
      @latitude = Array(latitude).dup
      @longitude = Array(longitude).dup
    end

    def to_geojson
      {
        type: "Feature",
        geometry: {
          type: "LineString",
          properties: {},
          coordinates: @longitude.zip(@latitude).map { |lon, lat| [ lon, lat ] }
        }
      }.to_json
    end
  end

  serialize :positions, coder: Positions

  def parse_fit_file(fit_file)
    str = fit_file.try(:read) || fit_file.download
    RubyFit::Parser.new(FitExtractor.new(self)).parse(str)
  end

  def active_time_duration
    ActiveSupport::Duration.parse(active_time)
  end

  def duration
    ActiveSupport::Duration.build((end_time - start_time).to_i)
  end
end
