class ActivityFeedsController < ApplicationController
  def index
    base = Current.user.activities

    @period_week  = period_stats(base, 7.days.ago.beginning_of_day..)
    @period_month = period_stats(base, Time.current.beginning_of_month..)
    @period_year  = period_stats(base, Time.current.beginning_of_year..)

    cycling_sports = Activity::SPORT_CATEGORY.select { |_, v| v == :cycling }.keys.map(&:to_s)
    running_sports = Activity::SPORT_CATEGORY.select { |_, v| v == :running }.keys.map(&:to_s)

    @cycling_records = personal_records(base, cycling_sports)
    @running_records  = personal_records(base, running_sports)

    @recent_activities = base.order(start_time: :desc).limit(5)
  end

  private

  def period_stats(base, range)
    rows = base.where(start_time: range)
               .pluck(:active_time, :distance, :total_elevation_gain)
    {
      count:          rows.size,
      distance_km:    (rows.sum { |_, d, _| d.to_f } / 1000.0).round(2),
      total_seconds:  rows.sum { |at, _, _| parse_seconds(at) },
      elevation_gain: rows.sum { |_, _, e| e.to_f }.round.to_i
    }
  end

  def personal_records(base, sports)
    scope = base.where(sport: sports)
    return nil unless scope.exists?

    {
      longest_distance: scope.where.not(distance: nil)
                             .order(distance: :desc)
                             .select(:id, :name, :distance)
                             .first,
      most_elevation:   scope.where.not(total_elevation_gain: nil)
                             .order(total_elevation_gain: :desc)
                             .select(:id, :name, :total_elevation_gain)
                             .first,
      fastest_speed:    scope.where.not(max_speed: nil)
                             .order(max_speed: :desc)
                             .select(:id, :name, :max_speed)
                             .first
    }
  end

  def parse_seconds(iso8601_string)
    return 0 if iso8601_string.blank?
    ActiveSupport::Duration.parse(iso8601_string).to_i
  rescue ActiveSupport::Duration::ISO8601DurationError
    0
  end
end
