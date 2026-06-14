require "test_helper"

class PlannedRouteTest < ActiveSupport::TestCase
  test "ROUTABLE_SPORTS excludes non-routable Activity sports" do
    %i[virtual_ride virtual_run alpine_ski nordic_ski swim workout].each do |excluded|
      assert_not_includes PlannedRoute::ROUTABLE_SPORTS, excluded
    end
  end

  test "every routable sport maps to a BRouter profile" do
    PlannedRoute::ROUTABLE_SPORTS.each do |sport|
      assert PlannedRoute::BROUTER_PROFILE.key?(sport),
             "missing BRouter profile mapping for #{sport}"
    end
  end

  test "validates waypoints shape" do
    base = { user: users(:one), name: "x", sport: "bike" }
    assert PlannedRoute.new(base.merge(waypoints: [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [ [ 1.0, 2.0 ] ])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [ [ 200.0, 2.0 ], [ 3.0, 4.0 ] ])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [ [ "a", 2.0 ], [ 3.0, 4.0 ] ])).valid?
  end

  test "sport_category and sport_icon_name delegate to Activity mapping" do
    pr = PlannedRoute.new(sport: "mountain_bike_ride")
    assert_equal :cycling, pr.sport_category
    assert_equal "bike", pr.sport_icon_name
  end

  test "path_geojson is nil without a path" do
    assert_nil PlannedRoute.new.path_geojson
  end

  test "elevation_chart_data returns nil without samples" do
    assert_nil PlannedRoute.new.elevation_chart_data
    assert_nil PlannedRoute.new(elevation_samples: []).elevation_chart_data
  end

  test "elevation_chart_data splits samples into labels and data arrays" do
    pr = PlannedRoute.new(elevation_samples: [ [ 0, 10 ], [ 111, 12 ], [ 222, 11 ] ])
    chart = pr.elevation_chart_data
    assert_equal [ 0, 111, 222 ], chart[:labels]
    assert_equal [ 10, 12, 11 ], chart[:data]
  end

  test "path_coordinates is empty without a path" do
    assert_equal [], PlannedRoute.new.path_coordinates
  end
end
