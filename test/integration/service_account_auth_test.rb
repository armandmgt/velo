require "test_helper"

class ServiceAccountAuthTest < ActionDispatch::IntegrationTest
  setup do
    # A service account has no user behind it; access is granted purely by the
    # service-account session, exercising the token auth path specifically.
    @session = Session.create!(service_account: true)
    @token = @session.generate_token_for(:service_account_api)
  end

  test "bearer token for a service account is authorized on admin routes" do
    get admin_users_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success
  end

  test "request without a token is not authorized" do
    get admin_users_path
    assert_redirected_to new_session_path
  end

  test "invalid bearer token is not authorized" do
    get admin_users_path, headers: { "Authorization" => "Bearer not-a-real-token" }
    assert_redirected_to new_session_path
  end

  test "token minted from a non-service-account session is rejected" do
    # The token is only as good as the flag on the session it came from — otherwise any
    # logged-in user could mint themselves API access.
    regular_session = users(:two).sessions.create!
    token = regular_session.generate_token_for(:service_account_api)

    get admin_users_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_redirected_to new_session_path
  end

  test "token no longer works once the service-account session is destroyed" do
    @session.destroy

    get admin_users_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_redirected_to new_session_path
  end

  test "a service-account token is not accepted outside the admin namespace" do
    # Bearer auth is deliberately scoped to Admin::AdminController; everywhere else a
    # session still means a person with a cookie.
    get root_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_redirected_to new_session_path
  end

  test "a service account session is valid without a user" do
    assert Session.new(service_account: true).valid?
  end

  test "an ordinary session still requires a user" do
    assert_not Session.new.valid?
  end
end
