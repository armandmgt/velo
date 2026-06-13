require "test_helper"

class RoutePlannerTest < ActiveSupport::TestCase
  test "passes the sport-mapped profile to the client and builds a SRID LINESTRING" do
    fake_client = Object.new
    captured = {}

    fake_client.define_singleton_method(:route) do |waypoints:, profile:|
      captured[:waypoints] = waypoints
      captured[:profile]   = profile
      BRouterClient::Route.new(
        coordinates:           [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ],
        distance_meters:       1234,
        elevation_gain_meters: 56
      )
    end

    result = RoutePlanner.new(
      sport: "mountain_bike_ride",
      waypoints: [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ],
      client: fake_client
    ).call

    assert_equal "mtb", captured[:profile]
    assert_equal [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ], captured[:waypoints]
    assert_equal "SRID=4326;LINESTRING(1.0 2.0, 3.0 4.0)", result.path_wkt
    assert_equal 1234, result.distance_meters
    assert_equal 56, result.elevation_gain_meters
    assert_equal "mtb", result.profile
  end

  test "road bike maps to fastbike profile" do
    fake_client = Object.new
    captured_profile = nil
    fake_client.define_singleton_method(:route) do |waypoints:, profile:|
      captured_profile = profile
      BRouterClient::Route.new(coordinates: [ [ 0.0, 0.0 ], [ 1.0, 1.0 ] ], distance_meters: 0, elevation_gain_meters: 0)
    end

    RoutePlanner.new(sport: "bike", waypoints: [ [ 0.0, 0.0 ], [ 1.0, 1.0 ] ], client: fake_client).call
    assert_equal "fastbike", captured_profile
  end

  test "run maps to hiking-beta profile" do
    fake_client = Object.new
    captured_profile = nil
    fake_client.define_singleton_method(:route) do |waypoints:, profile:|
      captured_profile = profile
      BRouterClient::Route.new(coordinates: [ [ 0.0, 0.0 ], [ 1.0, 1.0 ] ], distance_meters: 0, elevation_gain_meters: 0)
    end

    RoutePlanner.new(sport: "run", waypoints: [ [ 0.0, 0.0 ], [ 1.0, 1.0 ] ], client: fake_client).call
    assert_equal "hiking-beta", captured_profile
  end
end
