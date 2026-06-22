require "test_helper"

class Shared::ActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @shareable = activities(:shareable)
    @private   = activities(:one)
  end

  test "renders shareable activity without authentication" do
    token = @shareable.signed_id(purpose: :share)
    get shared_activity_url(token)
    assert_response :success
    assert_match @shareable.name, @response.body
  end

  test "does not render the owner navbar on the share layout" do
    token = @shareable.signed_id(purpose: :share)
    get shared_activity_url(token)
    assert_response :success
    assert_select "nav#navbar", false
  end

  test "hides heart rate zones on the share view" do
    token = @shareable.signed_id(purpose: :share)
    get shared_activity_url(token)
    assert_response :success
    assert_select "[data-controller~=stacked-bar]", false
  end

  test "returns 404 for a private activity even with a valid signed_id" do
    assert_predicate @private, :visibility_private?
    token = @private.signed_id(purpose: :share)
    get shared_activity_url(token)
    assert_response :not_found
  end

  test "returns 404 for a malformed token" do
    get shared_activity_url("not-a-real-token")
    assert_response :not_found
  end

  test "returns 404 for a token signed with a different purpose" do
    token = @shareable.signed_id(purpose: :something_else)
    get shared_activity_url(token)
    assert_response :not_found
  end

  test "share route does not require authentication (no redirect to sign-in)" do
    token = @shareable.signed_id(purpose: :share)
    get shared_activity_url(token)
    assert_response :success
    assert_no_match %r{/session/new}, @response.body
  end
end
