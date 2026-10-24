# An Activity's fastest stretch over a standard distance (see CONTEXT.md).
#
# `rank` is the PR / 2nd / 3rd standing the effort earned against the rider's
# earlier activities when it was ingested, and never changes afterwards. A
# removed effort (a GPS glitch the owner flagged) is kept so it can be restored,
# but drops out of records and of every later effort's ranking.
class BestEffort < ApplicationRecord
  MILE = 1609.344

  # Strava's standard distances, in metres.
  DISTANCES = {
    running: {
      "400m" => 400, "half_mile" => MILE / 2, "1k" => 1_000, "1_mile" => MILE,
      "2_miles" => 2 * MILE, "5k" => 5_000, "10k" => 10_000, "15k" => 15_000,
      "10_miles" => 10 * MILE, "20k" => 20_000, "half_marathon" => 21_097.5,
      "30k" => 30_000, "marathon" => 42_195, "50k" => 50_000
    },
    cycling: {
      "10k" => 10_000, "10_miles" => 10 * MILE, "20k" => 20_000, "40k" => 40_000,
      "50k" => 50_000, "50_miles" => 50 * MILE, "80k" => 80_000, "90k" => 90_000,
      "100k" => 100_000, "100_miles" => 100 * MILE, "180k" => 180_000
    },
    other: {}
  }.freeze

  METERS = DISTANCES.values.reduce(:merge).freeze

  # Fastest plausible sustained speed per category (m/s): above a world-class
  # sprint on foot, above a fast descent on a bike.
  MAX_SPEED = { running: 12.5, cycling: 28.0 }.freeze

  PODIUM = 3

  belongs_to :activity

  validates :distance, inclusion: { in: METERS.keys }
  validates :rank, inclusion: { in: 1..PODIUM }, allow_nil: true

  scope :kept, -> { where(removed_at: nil) }

  def self.sports_in(category)
    Activity::SPORT_CATEGORY.select { |_, cat| cat == category }.keys.map(&:to_s)
  end

  # Builds (without saving) the efforts an activity's located points yield.
  def self.build_for(activity, points)
    return [] unless activity.sport

    category  = activity.sport_category
    distances = DISTANCES.fetch(category)
    return [] if distances.empty?

    DistanceEfforts.new(points, distances:, max_speed: MAX_SPEED.fetch(category)).call.map do |effort|
      activity.best_efforts.build(
        distance:        effort.key,
        elapsed_seconds: effort.elapsed_seconds,
        start_index:     effort.start_index,
        end_index:       effort.end_index,
        rank:            rank_against_earlier(activity, effort.key, effort.elapsed_seconds)
      )
    end
  end

  def self.rank_against_earlier(activity, distance, elapsed_seconds)
    return unless activity.user

    faster = kept.joins(:activity)
      .where(distance:, activities: { user_id: activity.user_id, sport: sports_in(activity.sport_category) })
      .where(elapsed_seconds: ...elapsed_seconds)
      .where.not(activity_id: activity.id)
    faster = faster.where(activities: { start_time: ...activity.start_time }) if activity.start_time

    position = faster.count + 1
    position if position <= PODIUM
  end

  def meters
    METERS.fetch(distance)
  end

  def speed
    meters / elapsed_seconds
  end

  def removed?
    removed_at.present?
  end

  def remove!
    update!(removed_at: Time.current)
  end

  def restore!
    update!(removed_at: nil)
  end
end
