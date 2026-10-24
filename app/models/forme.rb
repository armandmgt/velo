# A rider's Forme over a chosen window: one curve across all sports, built from
# the effort scores of their activities, summed per local day.
class Forme
  WINDOWS = { "3m" => 3, "6m" => 6, "1y" => 12 }.freeze
  DEFAULT_WINDOW = "3m"
  TIME_ZONE = "Europe/Paris"
  COLORS = { fitness: "#3B82F6", fatigue: "#EC4899", form: "#F59E0B", load: "#9CA3AF" }.freeze

  attr_reader :window

  def initialize(user, window: nil, today: Time.current.in_time_zone(TIME_ZONE).to_date)
    @user = user
    @window = WINDOWS.key?(window) ? window : DEFAULT_WINDOW
    @today = today
  end

  def from
    @today - WINDOWS.fetch(window).months + 1.day
  end

  def days
    @days ||= FormeCurve.new(daily_loads).days(from: from, to: @today)
  end

  def current
    days.last
  end

  def unscored_activities_count
    @user.activities.where(effort_score: nil, start_time: from.in_time_zone(TIME_ZONE)..).count
  end

  def chart_data
    {
      labels: days.map { |day| day.date.iso8601 },
      load: days.map { |day| day.load.positive? ? day.load.round : nil },
      fitness: days.map { |day| day.fitness.round(1) },
      fatigue: days.map { |day| day.fatigue.round(1) },
      form: days.map { |day| day.form.round(1) }
    }
  end

  private

  def daily_loads
    @user.activities.scored.where(start_time: ..@today.in_time_zone(TIME_ZONE).end_of_day)
         .pluck(:start_time, :effort_score)
         .each_with_object(Hash.new(0)) do |(start_time, score), loads|
           loads[start_time.in_time_zone(TIME_ZONE).to_date] += score
         end
  end
end
