require "test_helper"

class GpxExtractorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @gpx = Rails.root.join("test/fixtures/files/gpx/ride.gpx").read
  end

  def extract(activity = @user.activities.build)
    GpxExtractor.new(activity, reverse_geocode: false).extract(@gpx)
    activity
  end

  test "builds a data point per track point" do
    activity = extract
    assert_equal 5, activity.activity_data_points.size
  end

  test "computes distance from track points via haversine" do
    activity = extract
    assert_in_delta 496.8, activity.distance.to_f, 1.0
  end

  test "computes elevation gain with a noise threshold" do
    # 44.5 -> 46.0 (+1.5, below 3m threshold, ignored) -> 52.0 (+7.5) -> 49.0 -> 58.0 (+9.0)
    activity = extract
    assert_in_delta 16.5, activity.total_elevation_gain.to_f, 0.1
  end

  test "computes moving time as active_time" do
    activity = extract
    assert_equal "PT40S", activity.active_time
  end

  test "sets start and end time from first/last point" do
    activity = extract
    assert_equal Time.utc(2026, 3, 29, 7, 49, 28), activity.start_time
    assert_equal Time.utc(2026, 3, 29, 7, 50, 8), activity.end_time
  end

  test "records max speed and per-point metrics" do
    activity = extract
    assert_operator activity.max_speed.to_f, :>, 0
    assert_equal 110, activity.activity_data_points.first.heart_rate
    assert_equal 44.5, activity.activity_data_points.first.altitude.to_f
  end

  test "builds a PostGIS LineString path" do
    activity = extract
    assert_kind_of RGeo::Feature::LineString, activity.path
    assert_equal 5, activity.path.num_points
  end

  test "falls back to name and sport from the GPX track" do
    activity = extract
    assert_equal "Petite sortie GPX", activity.name
    assert_equal "mountain_bike_ride", activity.sport
  end

  test "does not override a sport already set on the activity" do
    activity = extract(@user.activities.build(sport: :gravel_ride))
    assert_equal "gravel_ride", activity.sport
  end

  test "persists end to end" do
    activity = extract
    assert activity.save, activity.errors.full_messages.to_sentence
    assert_equal 5, activity.reload.activity_data_points.count
  end
end
