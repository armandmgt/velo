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

  test "should send a verification email and leave the new user unverified" do
    assert_enqueued_emails 1 do
      post users_url, params: { user: { email_address: "four@example.com", password: "password" } }
    end

    new_user = User.find_by(email_address: "four@example.com")
    assert_not new_user.email_verified?
    assert_enqueued_email_with EmailVerificationsMailer, :verify, args: [ new_user ]
  end

  test "should show user" do
    login(@user)
    get user_url
    assert_response :success
  end

  test "should update max_heart_rate" do
    login(@user)
    patch user_url, params: { user: { max_heart_rate: 188 } }

    assert_redirected_to user_path
    assert_equal 188, @user.reload.max_heart_rate
  end

  test "should reject an out-of-range max_heart_rate" do
    login(@user)
    patch user_url, params: { user: { max_heart_rate: 50 } }

    assert_response :unprocessable_content
    assert_nil @user.reload.max_heart_rate
  end

  test "should destroy user" do
    login(@user)
    assert_difference("User.count", -1) do
      delete user_url
    end

    assert_redirected_to new_session_path
  end
end
