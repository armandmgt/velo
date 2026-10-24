# Power analysis of a ride with power data: normalized power and the power curve
# are derived at ingestion and stored; Coggan's zones and the TSS effort score
# depend on the rider's FTP, so they're derived from the samples whenever FTP is
# applied.
#
# Rides only, as on Strava: FTP is a cycling threshold, and running power isn't
# on the same scale.
module ActivityPower
  extend ActiveSupport::Concern

  # Coggan's seven zones as a share of FTP. `upper_ratio` is the exclusive upper
  # bound; the last zone catches everything above 150 %. `css_class` must match
  # the `.power-zone-*` rules in app/assets/tailwind/application.css.
  POWER_ZONES = [
    { label_key: "activity.power_zone.z1", upper_ratio: 0.55, css_class: "power-zone-1" },
    { label_key: "activity.power_zone.z2", upper_ratio: 0.75, css_class: "power-zone-2" },
    { label_key: "activity.power_zone.z3", upper_ratio: 0.90, css_class: "power-zone-3" },
    { label_key: "activity.power_zone.z4", upper_ratio: 1.05, css_class: "power-zone-4" },
    { label_key: "activity.power_zone.z5", upper_ratio: 1.20, css_class: "power-zone-5" },
    { label_key: "activity.power_zone.z6", upper_ratio: 1.50, css_class: "power-zone-6" },
    { label_key: "activity.power_zone.z7", upper_ratio: nil,  css_class: "power-zone-7" }
  ].freeze

  # Durations the power curve is sampled at, in seconds: dense where the curve
  # bends, sparser past an hour.
  CURVE_LADDER = [
    *1..10, *(15..60).step(5), *(75..300).step(15), *(360..1_200).step(60),
    *(1_500..3_600).step(300), *(4_200..12 * 3_600).step(600)
  ].freeze

  # Seconds in each zone, ordered Z1..Z7, from `[recorded_at, watts]` pairs in
  # time order. Each interval counts for its leading sample, as for heart rate;
  # an interval longer than the sample gap cap is a dropout and counts for none.
  def self.zone_seconds(samples, ftp)
    seconds = Array.new(POWER_ZONES.size, 0.0)
    samples.each_cons(2) do |(t_cur, watts), (t_next, _)|
      dt = t_next - t_cur
      seconds[zone_index(watts, ftp)] += dt if dt <= ActivityHeartRateZones::MAX_SAMPLE_GAP
    end
    seconds
  end

  def self.zone_index(watts, ftp)
    POWER_ZONES.index { |zone| zone[:upper_ratio] && watts < zone[:upper_ratio] * ftp } || POWER_ZONES.size - 1
  end

  def power_analysed_sport?
    sport.present? && sport_category == :cycling
  end

  def power_data?
    normalized_power.present?
  end

  # `[recorded_at, watts]` pairs in time order, read from memory during
  # ingestion.
  def power_samples
    return [] unless power_analysed_sport?

    if new_record?
      activity_data_points.filter_map { |point| [ point.recorded_at, point.power.to_f ] if point.power && point.recorded_at }
                          .sort_by(&:first)
    else
      activity_data_points.where.not(power: nil).order(:recorded_at).pluck(:recorded_at, :power)
                          .map { |time, watts| [ time, watts.to_f ] }
    end
  end

  def power_series
    PowerSeries.new(power_samples)
  end

  def assign_power_analysis(series = power_series)
    self.normalized_power = series.normalized_power&.round(1)
    curve = series.curve(CURVE_LADDER)
    self.power_curve = curve.presence
  end

  # TSS = duration × NP × IF / (FTP × 3600) × 100, with IF = NP / FTP. Duration
  # is the time covered by power data. Activities stored before power analysis
  # existed have no NP until the backfill reaches them, and keep their
  # heart-rate score meanwhile.
  def power_effort_score(ftp)
    return unless ftp && (new_record? || power_data?)

    series = power_series
    np = series.normalized_power or return
    (series.seconds * np * (np / ftp) / (ftp * 3600.0) * 100).round(1)
  end

  # nil without FTP or power. Otherwise an ordered array of
  #   { index:, label:, min_watts:, max_watts:, css_class:, seconds:, percent: }
  def power_zone_distribution(ftp)
    return unless ftp && power_data?

    seconds = ActivityPower.zone_seconds(power_samples, ftp)
    total = seconds.sum
    return if total.zero?

    bounds = POWER_ZONES.map { |zone| zone[:upper_ratio] && (zone[:upper_ratio] * ftp).round }
    POWER_ZONES.map.with_index do |zone, index|
      {
        index:,
        label: I18n.t(zone[:label_key]),
        min_watts: index.zero? ? 0 : bounds[index - 1],
        max_watts: bounds[index],
        css_class: zone[:css_class],
        seconds: seconds[index].round,
        percent: (seconds[index] / total * 100).round
      }
    end
  end
end
