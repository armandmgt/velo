require "test_helper"

class RecomputeEffortScoresJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.update_columns(max_heart_rate: 200)
    @with_hr = activities(:one)
    @with_hr.activity_data_points.destroy_all
    t = Time.zone.parse("2026-01-01 10:00:00")
    # 60 s in Z2 at max HR 200, Z1 at max HR 240.
    7.times { |i| @with_hr.activity_data_points.create!(recorded_at: t + (i * 10).seconds, heart_rate: 130) }
  end

  test "rescores all of the user's activities with their current max HR" do
    RecomputeEffortScoresJob.perform_now(@user)
    assert_equal 2, @with_hr.reload.effort_score

    @user.update_columns(max_heart_rate: 240)
    RecomputeEffortScoresJob.perform_now(@user)
    assert_equal 1, @with_hr.reload.effort_score
  end

  test "leaves activities without heart rate unscored and other users untouched" do
    other = activities(:two)
    other.update_columns(effort_score: 42, effort_score_source: "heart_rate")

    RecomputeEffortScoresJob.perform_now(@user)

    assert_nil activities(:this_week_ride).reload.effort_score
    assert_equal 42, other.reload.effort_score
  end
end
