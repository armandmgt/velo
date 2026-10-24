require "test_helper"

class FormeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @today = Date.new(2026, 3, 31)
  end

  test "defaults to a 3-month window and ignores unknown windows" do
    assert_equal "3m", Forme.new(@user, today: @today).window
    assert_equal "3m", Forme.new(@user, window: "bogus", today: @today).window
    assert_equal "1y", Forme.new(@user, window: "1y", today: @today).window
  end

  test "covers each day of the window, ending today" do
    days = Forme.new(@user, window: "6m", today: @today).days

    assert_equal Date.new(2025, 10, 1), days.first.date
    assert_equal @today, days.last.date
  end

  test "sums the scores of one local day across sports" do
    # 23:30 UTC on the 29th is already the 30th in Paris.
    scored(Time.utc(2026, 3, 29, 23, 30), 60, sport: :run)
    scored(Time.utc(2026, 3, 30, 17, 0), 40, sport: :bike)

    day = Forme.new(@user, today: @today).days.find { |d| d.date == Date.new(2026, 3, 30) }

    assert_equal 100, day.load
    assert_in_delta 100.0 / 42, day.fitness, 0.001
  end

  test "a user with no scores gets a flat curve and counts unscored activities" do
    forme = Forme.new(@user, today: Time.current.to_date)

    assert(forme.days.all? { |day| day.fitness.zero? })
    assert_equal @user.activities.where(start_time: forme.from.in_time_zone(Forme::TIME_ZONE)..).count,
                 forme.unscored_activities_count
    assert_operator forme.unscored_activities_count, :>, 0
  end

  test "chart data leaves load empty on rest days" do
    scored(Time.utc(2026, 3, 30, 10, 0), 100)

    data = Forme.new(@user, today: @today).chart_data

    assert_equal "2026-03-31", data[:labels].last
    assert_equal [ 100, nil ], data[:load].last(2)
    assert_equal data[:labels].size, data[:fitness].size
  end

  private

  def scored(start_time, score, sport: :bike)
    @user.activities.create!(name: "x", sport: sport, start_time: start_time, end_time: start_time + 1.hour,
                             location: "Paris", active_time: "PT3600S", effort_score: score, effort_score_source: :heart_rate)
  end
end
