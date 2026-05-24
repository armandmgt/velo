module ActivityHeartRateZones
  extend ActiveSupport::Concern

  # 5 zones as a percentage of max HR. `upper_ratio` is the exclusive upper
  # bound of each zone (the last zone catches everything at/above 0.90).
  # `color` (hex) tints the HR chart line (canvas, see ActivityCharts#chart_data);
  # `css_class` colors the DOM bar/table. Both must stay in sync with the
  # `.hr-zone-*` rules in app/assets/tailwind/application.css.
  HR_ZONES = [
    { key: :z1, label_key: "activity.heart_rate_zone.z1", upper_ratio: 0.60, color: "#9CA3AF", css_class: "hr-zone-1" },
    { key: :z2, label_key: "activity.heart_rate_zone.z2", upper_ratio: 0.70, color: "#3B82F6", css_class: "hr-zone-2" },
    { key: :z3, label_key: "activity.heart_rate_zone.z3", upper_ratio: 0.80, color: "#10B981", css_class: "hr-zone-3" },
    { key: :z4, label_key: "activity.heart_rate_zone.z4", upper_ratio: 0.90, color: "#F59E0B", css_class: "hr-zone-4" },
    { key: :z5, label_key: "activity.heart_rate_zone.z5", upper_ratio: nil,  color: "#EF4444", css_class: "hr-zone-5" }
  ].freeze

  # Cap the gap between consecutive samples so pauses (or sparse GPX tracks)
  # don't inflate time-in-zone. Mirrors GpxExtractor::PAUSE_GAP_SECONDS.
  MAX_SAMPLE_GAP = 10

  included do
    # Returns nil unless a max HR reference is set and the activity has HR data.
    # Otherwise an ordered array of zone breakdowns:
    #   { index:, label:, min_bpm:, max_bpm:, color:, seconds:, percent: }
    def heart_rate_zone_distribution(max_hr)
      return nil unless max_hr

      samples = activity_data_points
                  .where.not(heart_rate: nil)
                  .order(:recorded_at)
                  .pluck(:recorded_at, :heart_rate)
      return nil if samples.empty?

      seconds = Array.new(HR_ZONES.size, 0)
      samples.each_cons(2) do |(t_cur, hr_cur), (t_next, _)|
        dt = [ (t_next - t_cur).to_i, MAX_SAMPLE_GAP ].min
        seconds[hr_zone_index(hr_cur, max_hr)] += dt
      end

      total = seconds.sum
      return nil if total.zero?

      boundaries = zone_boundaries_bpm(max_hr)
      HR_ZONES.map.with_index do |zone, index|
        {
          index: index,
          label: I18n.t(zone[:label_key]),
          min_bpm: index.zero? ? 0 : boundaries[index - 1],
          max_bpm: boundaries[index],
          css_class: zone[:css_class],
          seconds: seconds[index],
          percent: (seconds[index].to_f / total * 100).round
        }
      end
    end

    private

    # Index of the first zone whose exclusive upper bound the HR falls under,
    # defaulting to the last zone (Z5).
    def hr_zone_index(heart_rate, max_hr)
      HR_ZONES.index { |zone| zone[:upper_ratio] && heart_rate < zone[:upper_ratio] * max_hr } || HR_ZONES.size - 1
    end

    # Upper bpm bound per zone; the last zone has no upper bound (nil).
    def zone_boundaries_bpm(max_hr)
      HR_ZONES.map { |zone| zone[:upper_ratio] && (zone[:upper_ratio] * max_hr).round }
    end
  end
end
