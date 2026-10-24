# One pass over a segment within an Activity (see CONTEXT.md). Indices refer to
# the activity's located points, which are also its path's vertices.
#
# `rank` is the PR / 2nd / 3rd standing earned against the rider's earlier
# efforts on the segment — including private ones and earlier passes in the
# same activity — fixed at ingestion. `private` keeps an effort off the
# leaderboard; it follows the activity's visibility and hidden portion.
class SegmentEffort < ApplicationRecord
  PODIUM = BestEffort::PODIUM

  belongs_to :segment
  belongs_to :activity

  validates :rank, inclusion: { in: 1..PODIUM }, allow_nil: true

  # Builds (without saving) the efforts an activity's located points yield on
  # every segment they pass by.
  def self.build_for(activity, points)
    return [] unless activity.sport && points.size >= 2
    return [] unless Segment::CATEGORIES.include?(activity.sport_category.to_s)

    Segment.where(sport_category: activity.sport_category.to_s).passed_by(points)
      .flat_map { |segment| build_on(segment, activity, points) }
  end

  def self.build_on(segment, activity, points)
    earlier = []
    SegmentMatcher.new(segment.vertices, points).call.map do |match|
      rank = rank_against_earlier(activity, segment, match.elapsed_seconds, earlier)
      earlier << match.elapsed_seconds
      activity.segment_efforts.build(
        segment:, rank:, private: activity.visibility_private? || activity.map_hidden?,
        start_index: match.start_index, end_index: match.end_index, elapsed_seconds: match.elapsed_seconds
      )
    end
  end

  def self.rank_against_earlier(activity, segment, elapsed_seconds, earlier_in_activity)
    return unless activity.user_id

    faster = joins(:activity)
      .where(segment:, activities: { user_id: activity.user_id })
      .where(elapsed_seconds: ...elapsed_seconds)
      .where.not(activity_id: activity.id)
    faster = faster.where(activities: { start_time: ...activity.start_time }) if activity.start_time

    position = faster.count + earlier_in_activity.count { it < elapsed_seconds } + 1
    position if position <= PODIUM
  end

  # A private activity keeps all its efforts private; otherwise an effort is
  # private when its start or end falls in the activity's hidden portion, which
  # would place the rider there.
  def self.refresh_privacy(activity)
    efforts = activity.segment_efforts.reject(&:destroyed?)
    return if efforts.empty?

    hidden = MapVisibility.new(activity, viewer: nil).hidden_vertex_indices unless activity.visibility_private?
    efforts.each do |effort|
      private = hidden.nil? || hidden.include?(effort.start_index) || hidden.include?(effort.end_index)
      effort.update_columns(private:) if effort.private != private
    end
  end

  def self.located_points(activity)
    activity.activity_data_points.where.not(location: nil).order(:recorded_at, :id).map do |point|
      Track::Point.new(recorded_at: point.recorded_at, lat: point.location.y, lon: point.location.x)
    end
  end

  def meters
    segment.distance
  end

  def speed
    meters / elapsed_seconds
  end

  # Always timed, never held watts — the best-effort helpers render both kinds.
  def power?
    false
  end
end
