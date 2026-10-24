require "test_helper"

class ActivityEffortScoreTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update_columns(max_heart_rate: 200)
    @activity = activities(:one)
    @activity.activity_data_points.destroy_all
  end

  # Max HR 200: Z2 is 120–139 bpm, Z4 is 160–179 bpm.
  test "scores 30 minutes in zone 2 and 10 minutes in zone 4 as 30×2 + 10×4 = 100" do
    add_samples([ [ 130, 30.minutes ], [ 170, 10.minutes ] ])

    @activity.recompute_effort_score!

    assert_equal 100, @activity.reload.effort_score
    assert @activity.effort_score_source_heart_rate?
  end

  test "an activity without heart rate gets no score" do
    @activity.activity_data_points.create!(recorded_at: Time.zone.parse("2026-01-01 10:00"), speed: 5)
    @activity.activity_data_points.create!(recorded_at: Time.zone.parse("2026-01-01 10:00:01"), speed: 5)

    @activity.recompute_effort_score!

    assert_nil @activity.reload.effort_score
    assert_nil @activity.effort_score_source
  end

  test "a user without max HR gets no score, and losing it clears an existing one" do
    add_samples([ [ 130, 10.minutes ] ])
    @activity.update_columns(effort_score: 20, effort_score_source: "heart_rate")
    @user.update_columns(max_heart_rate: nil)

    @activity.reload.recompute_effort_score!

    assert_nil @activity.reload.effort_score
    assert_nil @activity.effort_score_source
  end

  test "scores an unsaved activity from its in-memory data points" do
    activity = @user.activities.build
    t = Time.zone.parse("2026-01-01 10:00")
    activity.activity_data_points.build(recorded_at: t + 60, heart_rate: 190)
    activity.activity_data_points.build(recorded_at: t, heart_rate: 190)

    activity.assign_effort_score

    # One capped 10 s interval in Z5: 10/60 × 5
    assert_equal 0.8, activity.effort_score
  end

  test "bands a score against the median of recent scores" do
    assert_nil Activity.effort_band_for(100, [ 100, 100 ])
    assert_equal :typical, Activity.effort_band_for(100, [ 90, 100, 110 ])
    assert_equal :harder, Activity.effort_band_for(130, [ 90, 100, 110 ])
    assert_equal :much_harder, Activity.effort_band_for(200, [ 90, 100, 110 ])
    assert_equal :easier, Activity.effort_band_for(70, [ 90, 100, 110 ])
    assert_equal :much_easier, Activity.effort_band_for(30, [ 90, 100, 110, 120 ])
  end

  test "effort_band only looks at the rider's own scores from the previous weeks" do
    @activity.update_columns(effort_score: 130, effort_score_source: "heart_rate")
    [ 1, 2, 3 ].each do |n|
      scored(@user, @activity.start_time - n.weeks, 100)
    end
    scored(@user, @activity.start_time - 10.weeks, 1000)
    scored(users(:two), @activity.start_time - 1.week, 1000)

    assert_equal :harder, @activity.effort_band
  end

  private

  def add_samples(segments)
    t = Time.zone.parse("2026-01-01 10:00:00")
    rows = []
    segments.each do |heart_rate, duration|
      duration.to_i.times do
        rows << { activity_id: @activity.id, recorded_at: t, heart_rate: heart_rate, created_at: t, updated_at: t }
        t += 1
      end
    end
    rows << { activity_id: @activity.id, recorded_at: t, heart_rate: segments.last.first, created_at: t, updated_at: t }
    ActivityDataPoint.insert_all!(rows)
  end

  def scored(user, start_time, score)
    user.activities.create!(name: "x", sport: :bike, start_time: start_time, end_time: start_time + 1.hour,
                            location: "Paris", active_time: "PT3600S", effort_score: score, effort_score_source: :heart_rate)
  end
end
