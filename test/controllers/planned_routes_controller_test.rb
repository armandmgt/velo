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
    assert_equal "trekking", @planned_route.routing_profile
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

  # Rails deserializes a JSON body before the action sees it, but a form-encoded
  # post leaves waypoints as a String. Both have to work.
  test "preview accepts a form-encoded waypoints json string" do
    stub_brouter_success

    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: [ [ 0.0, 0.0 ], [ 0.001, 0.0 ] ].to_json },
         headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal 1234, JSON.parse(@response.body)["distance_meters"]
  end

  test "preview rejects a malformed waypoints payload" do
    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: "pas du json" },
         headers: { "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "invalid_input", JSON.parse(@response.body)["error"]
  end

  test "preview rejects non-numeric coordinates" do
    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: [ [ "a", 2.0 ], [ 3.0, 4.0 ] ] }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "invalid_input", JSON.parse(@response.body)["error"]
  end

  test "preview rejects more waypoints than the cap without calling BRouter" do
    stub_brouter_error
    waypoints = Array.new(PlannedRoute::MAX_WAYPOINTS + 1) { |i| [ 2.0 + (i * 0.001), 48.0 ] }

    post preview_planned_routes_url,
         params: { sport: "bike", waypoints: waypoints }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    # A 502 here would mean the request reached the raising stub.
    assert_response :unprocessable_content
    assert_equal "too_many_waypoints", JSON.parse(@response.body)["error"]
  end

  # --- import_gpx ------------------------------------------------------------

  test "import_gpx seeds waypoints from a timeless route track" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/route_no_time.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :success
    waypoints = JSON.parse(@response.body)["waypoints"]
    assert_operator waypoints.length, :>=, 2
    assert_in_delta 2.3522, waypoints.first[0], 0.000001
    assert_in_delta 48.8566, waypoints.first[1], 0.000001
    assert_in_delta 2.3572, waypoints.last[0], 0.000001
    assert_in_delta 48.8616, waypoints.last[1], 0.000001
  end

  test "import_gpx returns the track name" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/route_no_time.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal "Boucle planifiée", JSON.parse(@response.body)["name"]
  end

  test "import_gpx downsamples a dense track and keeps both ends" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/dense_track.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :success
    waypoints = JSON.parse(@response.body)["waypoints"]

    assert_operator waypoints.length, :<=, PlannedRoutesController::MAX_SEEDED_WAYPOINTS
    assert_operator waypoints.length, :>=, 2
    # The fixture starts at the base point and ends at the far end of the east leg.
    assert_in_delta 2.3522, waypoints.first[0], 0.000001
    assert_in_delta 48.8566, waypoints.first[1], 0.000001
    assert_in_delta 2.3522 + (149 * 0.00015), waypoints.last[0], 0.000001
  end

  test "import_gpx seeds from a route-style rtept export" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/route_rtept.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal 4, JSON.parse(@response.body)["waypoints"].length
  end

  test "import_gpx never calls BRouter" do
    stub_brouter_error

    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/route_no_time.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :success
  end

  test "import_gpx rejects a missing file" do
    post import_gpx_planned_routes_url, headers: { "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "gpx_missing", JSON.parse(@response.body)["error"]
  end

  # A plain string used to reach `.read` and raise NoMethodError as a 500.
  test "import_gpx rejects a non-upload gpx_source" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: "coucou" },
         headers: { "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "gpx_missing", JSON.parse(@response.body)["error"]
  end

  test "import_gpx rejects a file that is not a gpx" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("fit/bike.fit") },
         headers: { "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "gpx_invalid_type", JSON.parse(@response.body)["error"]
  end

  test "import_gpx rejects an oversized file" do
    oversized = Rack::Test::UploadedFile.new(
      StringIO.new("x" * (PlannedRoutesController::MAX_GPX_BYTES + 1)),
      "application/gpx+xml",
      original_filename: "enorme.gpx"
    )

    post import_gpx_planned_routes_url,
         params: { gpx_source: oversized },
         headers: { "Accept" => "application/json" }

    assert_response :content_too_large
    assert_equal "gpx_too_large", JSON.parse(@response.body)["error"]
  end

  test "import_gpx rejects an unreadable file" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/garbage.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "gpx_unreadable", JSON.parse(@response.body)["error"]
  end

  test "import_gpx rejects a gpx with no usable points" do
    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/empty.gpx") },
         headers: { "Accept" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "gpx_no_points", JSON.parse(@response.body)["error"]
  end

  test "import_gpx requires authentication" do
    reset!

    post import_gpx_planned_routes_url,
         params: { gpx_source: file_fixture_upload("gpx/route_no_time.gpx") }

    assert_redirected_to new_session_url
  end

  # The picker is rendered with name: nil so the browser never submits it, but
  # a hand-rolled post must not blow up or leak the param into the model either.
  test "create ignores an uploaded gpx_source" do
    stub_brouter_success

    assert_difference("PlannedRoute.count", 1) do
      post planned_routes_url, params: {
        planned_route: {
          name: "Avec fichier",
          sport: "bike",
          waypoints_json: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ].to_json,
          gpx_source: file_fixture_upload("gpx/ride.gpx")
        }
      }
    end

    assert_redirected_to planned_route_url(PlannedRoute.order(:created_at).last)
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
