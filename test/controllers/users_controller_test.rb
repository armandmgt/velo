require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get new" do
    get new_user_url
    assert_response :success
  end

  test "should create user" do
    assert_difference("User.count") do
      post users_url, params: { user: { email_address: "three@example.com", password: "password" } }
    end

    assert_redirected_to new_session_path
  end

  test "should show user" do
    login(@user)
    get user_url
    assert_response :success
  end

  test "should destroy user" do
    login(@user)
    assert_difference("User.count", -1) do
      delete user_url
    end

    assert_redirected_to new_session_path
  end
end
