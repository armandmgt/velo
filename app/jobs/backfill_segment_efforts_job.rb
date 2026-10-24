# Matches a new segment against every existing activity on the instance, as
# ingestion would have had the segment existed. Activities are walked oldest
# first so each effort is ranked against the rider's earlier ones; those that
# already hold efforts on the segment are skipped, so the job can run again.
class BackfillSegmentEffortsJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(segment)
    candidates(segment).pluck(:id).each do |id|
      activity = Activity.find(id)
      SegmentEffort.transaction do
        SegmentEffort.build_on(segment, activity, SegmentEffort.located_points(activity)).each(&:save!)
      end
      SegmentEffort.refresh_privacy(activity)
    end
  end

  private

  def candidates(segment)
    Activity
      .where(sport: BestEffort.sports_in(segment.sport_category.to_sym))
      .where.not(id: segment.segment_efforts.select(:activity_id))
      .where(<<~SQL, id: segment.id, tolerance: SegmentMatcher::START_END_TOLERANCE)
        ST_DWithin(path::geography, (SELECT start_point FROM segments WHERE id = :id), :tolerance)
        AND ST_DWithin(path::geography, (SELECT end_point FROM segments WHERE id = :id), :tolerance)
      SQL
      .order(:start_time, :id)
  end
end
