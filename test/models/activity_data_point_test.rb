require "test_helper"

class ActivityDataPointTest < ActiveSupport::TestCase
  # `recorded_at` uniqueness is scoped to the activity, not global. Two different
  # activities — here two different users — must be able to hold a point at the
  # same instant; a global unique index would 500 the second insert.
  test "two different activities can record a point at the same instant" do
    at = Time.utc(2026, 6, 27, 8, 0, 0)
    activities(:one).activity_data_points.create!(recorded_at: at)

    assert_nothing_raised do
      activities(:two).activity_data_points.create!(recorded_at: at)
    end
  end

  # Within a single activity, duplicate timestamps are still rejected (the
  # composite unique index), so the per-second sampling stays one point per second.
  test "a single activity still rejects a duplicate recorded_at" do
    at = Time.utc(2026, 6, 27, 9, 0, 0)
    activity = activities(:one)
    activity.activity_data_points.create!(recorded_at: at)

    assert_raises(ActiveRecord::RecordNotUnique) do
      activity.activity_data_points.create!(recorded_at: at)
    end
  end
end
