# Derives power analysis for rides ingested before it existed, from the data
# points already stored: normalized power, the power curve, and power best
# efforts. Walks each rider's rides oldest first so every effort is ranked
# against the ones before it, as ingestion would have, then rescores them so
# riders with an FTP get power effort scores. Rides already analysed are left
# alone, which makes the job safe to run again.
class BackfillPowerAnalysisJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      pending(user).order(:start_time, :id).pluck(:id).each { |id| backfill(Activity.find(id)) }
    end
  end

  private

  def pending(user)
    user.activities.where(sport: BestEffort.sports_in(:cycling), normalized_power: nil)
        .where(id: ActivityDataPoint.where.not(power: nil).select(:activity_id))
  end

  def backfill(activity)
    series = activity.power_series

    Activity.transaction do
      activity.assign_power_analysis(series)
      activity.update_columns(normalized_power: activity.normalized_power, power_curve: activity.power_curve)
      unless activity.best_efforts.power.exists?
        BestEffort.build_power_for(activity, series, located_points(activity)).each(&:save!)
      end
      activity.recompute_effort_score!
    end
  end

  def located_points(activity)
    activity.activity_data_points.where.not(location: nil).order(:recorded_at, :id).select(:recorded_at)
  end
end
