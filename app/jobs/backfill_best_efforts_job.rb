# Derives best efforts for activities ingested before they existed, from the
# data points already stored. Walks each rider's activities oldest first so
# every effort is ranked against the ones that came before it, as ingestion
# would have. Activities that already have efforts are left alone, which makes
# the job safe to run again.
class BackfillBestEffortsJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      user.activities.where.missing(:best_efforts).order(:start_time, :id).pluck(:id).each do |id|
        backfill(Activity.find(id))
      end
    end
  end

  private

  def backfill(activity)
    BestEffort.transaction do
      BestEffort.build_for(activity, located_points(activity)).each(&:save!)
    end
  end

  def located_points(activity)
    activity.activity_data_points.where.not(location: nil).order(:recorded_at, :id).map do |point|
      Track::Point.new(recorded_at: point.recorded_at, lat: point.location.y, lon: point.location.x)
    end
  end
end
