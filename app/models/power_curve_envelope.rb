# A rider's power curve across their rides: for every duration, the best
# average power any ride reached. Shown all-time against one comparison period
# (the last 90 days, this year, or a past year), as Strava frames it.
class PowerCurveEnvelope
  ZONE = PersonalRecords::ZONE
  DEFAULT_PERIOD = "90d"

  attr_reader :period

  def initialize(user, period: nil, today: Time.current.in_time_zone(ZONE).to_date)
    @user   = user
    @today  = today
    @period = periods.key?(period.to_s) ? period.to_s : DEFAULT_PERIOD
  end

  # { param => label }, most recent first.
  def periods
    @periods ||= {
      "90d" => I18n.t("power_curve.period.last_90_days"),
      "this_year" => I18n.t("power_curve.period.this_year")
    }.merge(past_years.to_h { |year| [ year.to_s, year.to_s ] })
  end

  def empty?
    all_time.empty?
  end

  # [[seconds, watts], ...] by increasing duration.
  def all_time
    @all_time ||= envelope(rides)
  end

  def compared
    @compared ||= envelope(rides.where(start_time: period_range))
  end

  def chart_data
    { all_time: points(all_time), compared: points(compared) }
  end

  private

  def rides
    @user.activities.where(sport: BestEffort.sports_in(:cycling)).where.not(power_curve: nil)
  end

  def envelope(scope)
    scope.joins("CROSS JOIN LATERAL jsonb_each_text(activities.power_curve) AS curve(seconds, watts)")
         .group(Arel.sql("curve.seconds::int"))
         .order(Arel.sql("curve.seconds::int"))
         .pluck(Arel.sql("curve.seconds::int"), Arel.sql("MAX(curve.watts::float)"))
  end

  def period_range
    zone = Time.find_zone(ZONE)
    case period
    when "90d"       then zone.local(@today.year, @today.month, @today.day) - 89.days..
    when "this_year" then zone.local(@today.year).all_year
    else zone.local(period.to_i).all_year
    end
  end

  def past_years
    rides.distinct
         .pluck(Arel.sql("EXTRACT(YEAR FROM start_time AT TIME ZONE 'UTC' AT TIME ZONE '#{ZONE}')::int"))
         .reject { |year| year >= @today.year }
         .sort.reverse
  end

  def points(curve)
    curve.map { |seconds, watts| { x: seconds, y: watts.round } }
  end
end
