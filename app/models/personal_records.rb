# A rider's current records in one sport category, optionally within a year:
# the top 3 kept best efforts per standard distance (and, for cycling, per
# power duration), plus Strava's two single-value ride records for cycling.
class PersonalRecords
  CATEGORIES = %i[cycling running].freeze
  ZONE = "Europe/Paris".freeze
  ACTIVITY_COLUMNS = %i[id name start_time distance total_elevation_gain sport].freeze

  attr_reader :category, :year

  def initialize(user, category:, year: nil)
    @user     = user
    @category = category
    @year     = year
  end

  def distances
    BestEffort::DISTANCES.fetch(category)
  end

  def power_durations
    category == :cycling ? BestEffort::POWER_DURATIONS : {}
  end

  # { effort key => [best, 2nd, 3rd] }, each effort carrying
  # `activity_name` and `activity_start_time`.
  def podiums
    @podiums ||= BestEffort
      .from(ranked_efforts, :best_efforts)
      .where("podium_position <= ?", BestEffort::PODIUM)
      .order(:distance, :podium_position)
      .group_by(&:distance)
  end

  def longest_ride
    ride_record(:distance)
  end

  def biggest_climb
    ride_record(:total_elevation_gain)
  end

  def years
    @user.activities.where(sport: BestEffort.sports_in(category))
      .distinct
      .pluck(Arel.sql("EXTRACT(YEAR FROM start_time AT TIME ZONE 'UTC' AT TIME ZONE '#{ZONE}')::int"))
      .sort.reverse
  end

  private

  def activities
    scope = @user.activities.where(sport: BestEffort.sports_in(category))
    year ? scope.where(start_time: Time.find_zone(ZONE).local(year).all_year) : scope
  end

  def ranked_efforts
    BestEffort.kept.joins(:activity).merge(activities).select(
      "best_efforts.*",
      "activities.name AS activity_name",
      "activities.start_time AS activity_start_time",
      "ROW_NUMBER() OVER (PARTITION BY best_efforts.distance " \
      "ORDER BY best_efforts.average_power DESC NULLS LAST, best_efforts.elapsed_seconds, " \
      "activities.start_time) AS podium_position"
    )
  end

  def ride_record(column)
    return unless category == :cycling

    activities.where(Activity.arel_table[column].gt(0)).order(column => :desc, start_time: :asc)
      .select(*ACTIVITY_COLUMNS).first
  end
end
