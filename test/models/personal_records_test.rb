require "test_helper"

class PersonalRecordsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  def activity(sport: :run, on: Time.utc(2026, 6, 1, 8), **attrs)
    @user.activities.create!(name: "Sortie #{on.to_date}", sport:, start_time: on, end_time: on + 1.hour,
                             location: "Paris", active_time: "PT3600S", **attrs)
  end

  def effort(seconds, distance: "5k", **activity_attrs)
    activity(**activity_attrs).best_efforts.create!(distance:, elapsed_seconds: seconds, start_index: 0, end_index: 1)
  end

  def podium(category: :running, year: nil, distance: "5k")
    PersonalRecords.new(@user, category:, year:).podiums.fetch(distance, []).map(&:elapsed_seconds)
  end

  test "the top 3 per distance, fastest first" do
    [ 1_500, 1_400, 1_600, 1_450 ].each_with_index { |s, i| effort(s, on: Time.utc(2026, 1, i + 1)) }

    assert_equal [ 1_400, 1_450, 1_500 ], podium
  end

  test "removing an effort promotes the next one, restoring it reverts that" do
    fastest = effort(1_400, on: Time.utc(2026, 1, 1))
    [ 1_450, 1_500, 1_550 ].each_with_index { |s, i| effort(s, on: Time.utc(2026, 1, i + 2)) }

    fastest.remove!
    assert_equal [ 1_450, 1_500, 1_550 ], podium

    fastest.restore!
    assert_equal [ 1_400, 1_450, 1_500 ], podium
  end

  test "filters to one year and to the category's sports" do
    effort(1_400, on: Time.utc(2025, 6, 1))
    effort(1_500, on: Time.utc(2026, 6, 1))
    effort(900, sport: :bike, distance: "10k", on: Time.utc(2026, 6, 2))

    assert_equal [ 1_500 ], podium(year: 2026)
    assert_equal [ 1_400, 1_500 ], podium
    assert_empty podium(category: :cycling)
    assert_equal [ 2026, 2025 ], PersonalRecords.new(@user, category: :running).years
  end

  test "longest ride and biggest climb for cycling only" do
    long  = activity(sport: :bike, distance: 120_000, total_elevation_gain: 800)
    climb = activity(sport: :bike, distance: 60_000, total_elevation_gain: 1_900)
    activity(sport: :run, distance: 200_000, total_elevation_gain: 5_000)

    records = PersonalRecords.new(@user, category: :cycling)
    assert_equal long.id, records.longest_ride.id
    assert_equal climb.id, records.biggest_climb.id
    assert_nil PersonalRecords.new(@user, category: :running).longest_ride
  end
end
