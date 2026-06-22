require "test_helper"

class Shared::PlannedRoutesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @shareable = planned_routes(:shareable)
    @private   = planned_routes(:one)
  end

  test "renders shareable planned route without authentication" do
    token = @shareable.signed_id(purpose: :share)
    get shared_planned_route_url(token)
    assert_response :success
    assert_match @shareable.name, @response.body
  end

  test "returns 404 for a private planned route" do
    assert_predicate @private, :visibility_private?
    token = @private.signed_id(purpose: :share)
    get shared_planned_route_url(token)
    assert_response :not_found
  end

  test "returns 404 for a malformed token" do
    get shared_planned_route_url("not-a-real-token")
    assert_response :not_found
  end

  test "returns 404 for a token signed with a different purpose" do
    token = @shareable.signed_id(purpose: :something_else)
    get shared_planned_route_url(token)
    assert_response :not_found
  end

  test "streams a GPX document when format is gpx" do
    @shareable.update_columns(
      path: "SRID=4326;LINESTRING(2.35 48.85, 2.36 48.86)",
      elevation_samples: [ [ 0, 100 ], [ 111, 105 ] ]
    )
    token = @shareable.signed_id(purpose: :share)

    get shared_planned_route_url(token, format: :gpx)

    assert_response :success
    assert_equal "application/gpx+xml", @response.media_type
    assert_match(/<gpx /, @response.body)
    assert_match(/<trkpt /, @response.body)
  end

  test "returns 404 for the gpx format when the route is private" do
    token = @private.signed_id(purpose: :share)
    get shared_planned_route_url(token, format: :gpx)
    assert_response :not_found
  end
end
