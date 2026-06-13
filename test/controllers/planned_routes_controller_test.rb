require "test_helper"

class PlannedRoutesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @planned_route = planned_routes(:one)
    login(users(:one))
  end

  teardown do
    restore_brouter_client_new
  end

  test "index lists user's planned routes" do
    get planned_routes_url
    assert_response :success
    assert_match @planned_route.name, @response.body
  end

  test "new renders the form" do
    get new_planned_route_url
    assert_response :success
    assert_select "[data-controller~=route-planner]"
  end

  test "show renders" do
    get planned_route_url(@planned_route)
    assert_response :success
  end

  test "destroys a planned route" do
    assert_difference("PlannedRoute.count", -1) do
      delete planned_route_url(@planned_route)
    end
    assert_redirected_to planned_routes_url
  end

  test "create routes via BRouter and persists the planned route" do
    stub_brouter_success

    assert_difference("PlannedRoute.count") do
      post planned_routes_url, params: {
        planned_route: {
          name: "Tour matinal",
          sport: "bike",
          waypoints_json: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ].to_json
        }
      }
    end

    assert_redirected_to planned_route_url(PlannedRoute.last)
    persisted = PlannedRoute.last
    assert_equal "fastbike", persisted.routing_profile
    assert_equal 1234, persisted.distance_meters
    assert_equal 42, persisted.elevation_gain_meters
    assert_not_nil persisted.path
  end

  test "create rerenders new when BRouter has no route" do
    stub_brouter_no_route

    post planned_routes_url, params: {
      planned_route: {
        name: "Impossible",
        sport: "bike",
        waypoints_json: [ [ 0.0, 0.0 ], [ 100.0, 100.0 ] ].to_json
      }
    }

    assert_response :unprocessable_content
  end

  test "preview returns geojson and stats for valid input" do
    stub_brouter_success

    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ] }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "LineString", body.dig("geojson", "geometry", "type")
    assert_equal 1234, body["distance_meters"]
    assert_equal 42, body["elevation_gain_meters"]
  end

  test "preview rejects unknown sports" do
    post preview_planned_routes_url,
         params: { sport: "swim", waypoints: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ] }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :unprocessable_content
  end

  test "preview rejects fewer than two waypoints" do
    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: [ [ 2.35, 48.85 ] ] }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :unprocessable_content
  end

  private

  def stub_brouter_success
    fake_client = Object.new
    fake_client.define_singleton_method(:route) do |waypoints:, profile:|
      BRouterClient::Route.new(
        coordinates:           waypoints.dup,
        distance_meters:       1234,
        elevation_gain_meters: 42
      )
    end
    replace_brouter_client_new(fake_client)
  end

  def stub_brouter_no_route
    fake_client = Object.new
    fake_client.define_singleton_method(:route) { |**_| raise BRouterClient::NoRouteFound, "no track found" }
    replace_brouter_client_new(fake_client)
  end

  def replace_brouter_client_new(fake_client)
    BRouterClient.define_singleton_method(:new) { fake_client }
  end

  def restore_brouter_client_new
    if BRouterClient.singleton_class.instance_methods(false).include?(:new)
      BRouterClient.singleton_class.remove_method(:new)
    end
  end
end
