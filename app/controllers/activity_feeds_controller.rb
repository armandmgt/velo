class ActivityFeedsController < ApplicationController
  def index
    base = Current.user.activities

    @periods = DashboardStats.new(Current.user).periods

    cycling_sports = Activity::SPORT_CATEGORY.select { |_, v| v == :cycling }.keys.map(&:to_s)
    running_sports = Activity::SPORT_CATEGORY.select { |_, v| v == :running }.keys.map(&:to_s)

    @cycling_records = personal_records(base, cycling_sports)
    @running_records  = personal_records(base, running_sports)

    @recent_activities = base.order(start_time: :desc).limit(4)
  end

  private

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
end
