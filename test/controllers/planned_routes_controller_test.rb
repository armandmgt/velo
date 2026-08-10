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

  test "new yields a primary-styled bridge Save button into the navbar slot" do
    get new_planned_route_url
    assert_response :success

    # The hidden submit is the only bridge target on the page; default navbar
    # items have their bridge-target attribute stripped via the helper.
    assert_select %(button[type=submit][data-bridge--navbar-buttons-target=item][data-bridge-style=primary][form])
    assert_select %(a[href="#{user_path}"][data-bridge--navbar-buttons-target=item]), false,
                  "default Profil link should not be a bridge target when the form provides its own slot"
  end

  test "show renders" do
    get planned_route_url(@planned_route)
    assert_response :success
  end

  test "show.gpx streams a GPX document built from path points" do
    @planned_route.update_columns(
      path: "SRID=4326;LINESTRING(2.35 48.85, 2.36 48.86)",
      elevation_samples: [ [ 0, 100 ], [ 111, 105 ] ]
    )

    get planned_route_url(@planned_route, format: :gpx)

    assert_response :success
    assert_equal "application/gpx+xml", @response.media_type
    assert_match(/filename=".+\.gpx"/, @response.headers["Content-Disposition"])
    assert_match(/<gpx /, @response.body)
    assert_match(/<trkpt /, @response.body)
  end

  test "edit renders the form pre-seeded with waypoints" do
    get edit_planned_route_url(@planned_route)
    assert_response :success
    assert_select "[data-controller~=route-planner][data-route-planner-initial-waypoints-value*='2.3522']"
  end

  test "destroys a planned route" do
    assert_difference("PlannedRoute.count", -1) do
      delete planned_route_url(@planned_route)
    end
    assert_redirected_to planned_routes_url
  end

  test "update_visibility updates only visibility without calling BRouter" do
    BRouterClient.define_singleton_method(:new) { raise "BRouter should not be called" }

    patch visibility_planned_route_url(@planned_route),
          params: { planned_route: { visibility: "shareable" } }

    assert_redirected_to planned_route_url(@planned_route)
    assert_equal "shareable", @planned_route.reload.visibility
  end

  test "create routes via BRouter and persists the planned route" do
    stub_brouter_success

    assert_difference("PlannedRoute.count") do
      post planned_routes_url, params: {
        planned_route: {
          name: "Tour matinal",
          sport: "bike",
          waypoints_json: [ [ 0.0, 0.0 ], [ 0.001, 0.0 ] ].to_json
        }
      }
    end

    assert_redirected_to planned_route_url(PlannedRoute.last)
    persisted = PlannedRoute.last
    assert_equal "fastbike", persisted.routing_profile
    assert_equal 1234, persisted.distance_meters
    assert_equal 42, persisted.elevation_gain_meters
    assert_not_nil persisted.path
    assert_equal 2, persisted.elevation_samples.length
    assert_equal [ 0, 10 ], persisted.elevation_samples[0]
    assert_in_delta 111, persisted.elevation_samples[1][0], 2
    assert_equal 20, persisted.elevation_samples[1][1]
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

  test "update re-runs routing and persists changes" do
    stub_brouter_success

    patch planned_route_url(@planned_route), params: {
      planned_route: {
        name: "Tour mis à jour",
        sport: "gravel_ride",
        waypoints_json: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ].to_json
      }
    }

    assert_redirected_to planned_route_url(@planned_route)
    @planned_route.reload
    assert_equal "Tour mis à jour", @planned_route.name
    assert_equal "gravel_ride", @planned_route.sport
    assert_equal "mtb", @planned_route.routing_profile
    assert_equal 1234, @planned_route.distance_meters
  end

  test "update rerenders edit when BRouter fails" do
    stub_brouter_error

    patch planned_route_url(@planned_route), params: {
      planned_route: {
        name: @planned_route.name,
        sport: @planned_route.sport,
        waypoints_json: @planned_route.waypoints.to_json
      }
    }

    assert_response :unprocessable_content
  end

  test "preview returns geojson, coordinates and elevation samples" do
    stub_brouter_success

    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: [ [ 0.0, 0.0 ], [ 0.001, 0.0 ] ] }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "LineString", body.dig("geojson", "geometry", "type")
    assert_equal 1234, body["distance_meters"]
    assert_equal 42, body["elevation_gain_meters"]
    assert_equal 2, body["elevation_samples"].length
    assert_equal [ 0, 10 ], body["elevation_samples"][0]
    assert_in_delta 111, body["elevation_samples"][1][0], 2
    assert_equal 20, body["elevation_samples"][1][1]
    assert_kind_of Array, body["coordinates"]
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
        elevations:            [ 10.0, 20.0 ],
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

  def stub_brouter_error
    fake_client = Object.new
    fake_client.define_singleton_method(:route) { |**_| raise BRouterClient::Error, "boom" }
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
