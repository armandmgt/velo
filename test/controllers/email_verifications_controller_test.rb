require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:unverified) }

  test "show verifies the email with a valid token" do
    token = @user.generate_token_for(:email_verification)

    assert_changes -> { @user.reload.email_verified? }, from: false, to: true do
      get email_verification_path(token: token)
    end

    assert_redirected_to new_session_path
  end

  test "show rejects an invalid token" do
    assert_no_changes -> { @user.reload.email_verified? } do
      get email_verification_path(token: "invalid token")
    end

    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "div", /invalide ou a expiré/
  end

  test "create resends verification for an unconfirmed account" do
    assert_enqueued_email_with EmailVerificationsMailer, :verify, args: [ @user ] do
      post email_verification_path, params: { email_address: @user.email_address }
    end

    assert_redirected_to new_session_path
  end

  test "create sends nothing for an already-verified account" do
    assert_enqueued_emails 0 do
      post email_verification_path, params: { email_address: users(:one).email_address }
    end

    assert_redirected_to new_session_path
  end

  test "create sends nothing for an unknown address but redirects neutrally" do
    assert_enqueued_emails 0 do
      post email_verification_path, params: { email_address: "nobody@example.com" }
    end

    assert_redirected_to new_session_path
  end
end
