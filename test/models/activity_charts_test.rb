require "test_helper"

class ActivityChartsTest < ActiveSupport::TestCase
  test "elevation_chart_data returns nil when all data points have nil altitude" do
    activity = activities(:one)
    assert_nil activity.elevation_chart_data
  end

  test "elevation_chart_data returns labels and data when altitude present" do
    activity = activities(:one)
    activity.activity_data_points.first.update!(altitude: 250.5)

    result = activity.elevation_chart_data
    assert_not_nil result
    assert_equal activity.activity_data_points.count, result[:labels].size
    assert_equal activity.activity_data_points.count, result[:data].size
  end

  test "elevation_chart_data preserves nil entries for index alignment" do
    activity = activities(:one)
    points = activity.activity_data_points.order(:recorded_at).to_a

    # Add a second data point so we can have one with altitude and one without
    activity.activity_data_points.create!(
      recorded_at: points.first.recorded_at + 1.second,
      altitude: 300.0
    )

    result = activity.elevation_chart_data
    assert_includes result[:data], nil
    assert_includes result[:data], 300.0
  end
end
