# Computes the home dashboard datasets: four period views
# (Semaine / Mois / Année / Tout), each with a hero total, a trend delta,
# an "active buckets" streak count, and a normalized bar chart that
# re-buckets to match the selected period. Backs ActivityFeedsController#index.
class DashboardStats
  ZONE = "Europe/Paris".freeze

  Row = Struct.new(:time, :distance, :seconds, :elevation)

  def initialize(user, now: Time.current)
    @now = now.in_time_zone(ZONE)
    @rows = user.activities
                .pluck(:start_time, :distance, :active_time, :total_elevation_gain)
                .map do |start_time, distance, active_time, elevation|
      Row.new(start_time.in_time_zone(ZONE), distance.to_f, self.class.parse_seconds(active_time), elevation.to_f)
    end
  end

  def periods
    [ week_period, month_period, year_period, all_period ]
  end

  def self.parse_seconds(iso8601_string)
    return 0 if iso8601_string.blank?

    ActiveSupport::Duration.parse(iso8601_string).to_i
  rescue ActiveSupport::Duration::ISO8601DurationError
    0
  end

  private

  def week_period
    starts = (0..11).map { |i| @now.beginning_of_week - (11 - i).weeks }
    buckets = starts.map { |s| bucket(s, s + 1.week) }
    period(
      key: "week", tab: "Semaine",
      hero_label: "Distance · cette semaine",
      hero: buckets.last, buckets: buckets,
      active_count: active_buckets(buckets), active_label: "semaines actives",
      delta_pct: delta_to_date(starts.last, 1.week),
      chart_label: "12 dernières semaines",
      range_start: "il y a 12 sem.", range_end: "cette sem."
    )
  end

  def month_period
    starts = (0..11).map { |i| @now.beginning_of_month - (11 - i).months }
    buckets = starts.map { |s| bucket(s, s + 1.month) }
    period(
      key: "month", tab: "Mois",
      hero_label: "Distance · ce mois-ci",
      hero: buckets.last, buckets: buckets,
      active_count: active_buckets(buckets), active_label: "mois actifs",
      delta_pct: delta_to_date(starts.last, 1.month),
      chart_label: "12 derniers mois",
      range_start: "il y a 12 mois", range_end: "ce mois"
    )
  end

  def year_period
    starts = (0..4).map { |i| @now.beginning_of_year - (4 - i).years }
    buckets = starts.map { |s| bucket(s, s + 1.year) }
    period(
      key: "year", tab: "Année",
      hero_label: "Distance · cette année",
      hero: buckets.last, buckets: buckets,
      active_count: active_buckets(buckets), active_label: "années actives",
      delta_pct: delta_to_date(starts.last, 1.year),
      chart_label: "5 dernières années",
      range_start: starts.first.year.to_s, range_end: @now.year.to_s
    )
  end

  def all_period
    years = (first_year..@now.year).to_a
    buckets = years.map do |year|
      start = @now.beginning_of_year - (@now.year - year).years
      bucket(start, start + 1.year)
    end
    hero = {
      distance:  @rows.sum(&:distance),
      seconds:   @rows.sum(&:seconds),
      elevation: @rows.sum(&:elevation),
      count:     @rows.size
    }
    period(
      key: "all", tab: "Tout",
      hero_label: "Distance · depuis le début",
      hero: hero, buckets: buckets,
      active_count: @rows.size, active_label: "sorties au total",
      delta_pct: nil,
      chart_label: "par année",
      range_start: years.first.to_s, range_end: years.last.to_s
    )
  end

  def first_year
    @rows.map { |r| r.time.year }.min || @now.year
  end

  # Sum the metrics of every activity that started within [from, to).
  def bucket(from, to)
    rows = @rows.select { |r| r.time >= from && r.time < to }
    {
      distance:  rows.sum(&:distance),
      seconds:   rows.sum(&:seconds),
      elevation: rows.sum(&:elevation),
      count:     rows.size
    }
  end

  def active_buckets(buckets)
    buckets.count { |b| b[:distance].positive? }
  end

  # Like-for-like trend: this period so far vs. the previous period through the
  # same elapsed point (the current window shifted back by exactly one period).
  # Comparing against the *full* previous period would read negative all the way
  # through an in-progress week/month/year. Nil when either side is empty.
  def delta_to_date(period_start, length)
    current = bucket(period_start, @now)[:distance]
    previous = bucket(period_start - length, @now - length)[:distance]
    return nil if current <= 0 || previous <= 0

    (((current - previous) / previous) * 100).round
  end

  def period(key:, tab:, hero_label:, hero:, buckets:, active_count:, active_label:, delta_pct:, chart_label:, range_start:, range_end:)
    {
      key: key,
      tab: tab,
      hero_label: hero_label,
      distance_km: (hero[:distance] / 1000.0).round,
      count: hero[:count],
      time_seconds: hero[:seconds],
      elevation: hero[:elevation].round,
      delta_pct: delta_pct,
      active_count: active_count,
      total_buckets: buckets.size,
      active_label: active_label,
      bars: bars(buckets),
      chart_label: chart_label,
      range_start: range_start,
      range_end: range_end
    }
  end

  # Normalize bucket distances to bar heights (percent of the tallest bar).
  # The last bucket is the "current" one and gets the accent color; empty
  # buckets render as a short neutral stub.
  def bars(buckets)
    max = buckets.map { |b| b[:distance] }.max.to_f
    max = 1.0 if max <= 0
    last = buckets.size - 1

    buckets.each_with_index.map do |b, i|
      if b[:distance] <= 0
        { height: 0, state: "empty" }
      else
        { height: [ (b[:distance] / max * 100).round, 6 ].max,
          state: i == last ? "current" : "active" }
      end
    end
  end
end
