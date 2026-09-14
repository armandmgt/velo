# What a Source file yields once read: its points, its summary figures, and the
# name and sport the file itself suggests. See CONTEXT.md.
#
# A Track knows nothing about ActiveRecord — ActivityIngestion applies one to an
# Activity. That split is what lets the extractors be tested without a database.
#
# The summary is supplied by the extractor rather than derived here, because the
# two formats disagree about where it comes from and both are right: FIT reads
# device figures off the session message (wheel sensor, barometric altimeter),
# while GPX has no summary block and must compute from the points. See
# docs/adr/0004-ingestion-stops-before-persistence.md for the surrounding shape.
class Track
  # Mutable on purpose: SpeedFilter nulls outlier speeds in place.
  Point = Struct.new(
    :recorded_at, :lat, :lon, :altitude, :heart_rate, :cadence, :power, :speed,
    keyword_init: true
  ) do
    def located?
      !lat.nil? && !lon.nil?
    end
  end

  Summary = Data.define(
    :distance, :elevation_gain, :moving_seconds, :max_speed, :start_time, :end_time
  ) do
    def self.empty
      new(distance: 0.0, elevation_gain: 0.0, moving_seconds: 0.0,
          max_speed: nil, start_time: nil, end_time: nil)
    end
  end

  attr_reader :points, :summary, :suggested_name, :suggested_sport, :problems

  def initialize(points:, summary:, suggested_name: nil, suggested_sport: nil, problems: [])
    @points          = points
    @summary         = summary
    @suggested_name  = suggested_name
    @suggested_sport = suggested_sport
    @problems        = problems
  end

  def located_points
    @located_points ||= points.select(&:located?)
  end

  # The point a location name is resolved from.
  def first_fix
    located_points.first
  end

  def empty?
    points.empty?
  end
end
