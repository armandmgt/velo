module ActivityMetrics
  extend ActiveSupport::Concern

  included do
    def moving_seconds
      active_time_duration.to_i
    end

    def avg_speed_kmh
      return nil unless distance&.positive? && moving_seconds.positive?

      (distance / moving_seconds) * 3.6
    end

    def max_speed_kmh
      max_speed && max_speed * 3.6
    end

    # Pace in seconds per kilometer (running activities).
    def avg_pace_per_km
      return nil unless distance&.positive? && moving_seconds.positive?

      moving_seconds / (distance / 1000.0)
    end

    def avg_heart_rate
      activity_data_points.where.not(heart_rate: nil).average(:heart_rate)&.round
    end

    def max_heart_rate
      activity_data_points.maximum(:heart_rate)
    end

    def avg_power
      activity_data_points.where.not(power: nil).average(:power)&.round
    end

    def max_power
      activity_data_points.maximum(:power)&.round
    end

    def avg_cadence
      activity_data_points.where.not(cadence: nil).average(:cadence)&.round
    end

    def uses_pace?
      sport_category == :running
    end
  end
end
