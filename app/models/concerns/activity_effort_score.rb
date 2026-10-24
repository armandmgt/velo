# The Activity's effort score (see CONTEXT.md). The heart-rate score is
# zone-weighted TRIMP: minutes in each max-HR zone times the zone's number, so
# an hour in Z4 weighs four times an hour in Z1. `effort_score_source` exists so
# a power-based score can take precedence later without reshaping the data.
module ActivityEffortScore
  extend ActiveSupport::Concern

  # Bands compare a score with the median of the rider's own recent scores,
  # which is how Strava frames Relative Effort. Upper ratio bounds, exclusive.
  EFFORT_BANDS = [
    [ 0.6, :much_easier ],
    [ 0.85, :easier ],
    [ 1.15, :typical ],
    [ 1.5, :harder ],
    [ Float::INFINITY, :much_harder ]
  ].freeze
  EFFORT_BAND_LOOKBACK = 6.weeks
  EFFORT_BAND_MIN_HISTORY = 3

  included do
    enum :effort_score_source, %i[heart_rate].index_by(&:itself), prefix: true

    scope :scored, -> { where.not(effort_score: nil) }
  end

  class_methods do
    def effort_band_for(score, recent_scores)
      return if score.nil? || recent_scores.size < EFFORT_BAND_MIN_HISTORY

      sorted = recent_scores.map(&:to_f).sort
      mid = sorted.size / 2
      median = sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      return if median.zero?

      ratio = score.to_f / median
      EFFORT_BANDS.find { |limit, _| ratio < limit }.last
    end
  end

  def assign_effort_score
    score = heart_rate_effort_score(user&.max_heart_rate)
    self.effort_score = score
    self.effort_score_source = score && :heart_rate
  end

  # Skips callbacks: a max-HR change rescores every activity at once, and each
  # save would otherwise broadcast a page refresh.
  def recompute_effort_score!
    assign_effort_score
    return unless will_save_change_to_effort_score? || will_save_change_to_effort_score_source?

    update_columns(effort_score: effort_score, effort_score_source: effort_score_source)
  end

  def heart_rate_effort_score(max_hr)
    return unless max_hr

    seconds = ActivityHeartRateZones.zone_seconds(heart_rate_samples, max_hr)
    return if seconds.sum.zero?

    seconds.each_with_index.sum { |zone_seconds, index| zone_seconds / 60.0 * (index + 1) }.round(1)
  end

  def effort_band
    return unless effort_score

    recent = user.activities.scored.where.not(id: id)
                 .where(start_time: (start_time - EFFORT_BAND_LOOKBACK)...start_time)
                 .pluck(:effort_score)
    self.class.effort_band_for(effort_score, recent)
  end
end
