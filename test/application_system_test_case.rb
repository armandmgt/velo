require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Overridable so a machine without Chrome can run the suite:
  # SYSTEM_TEST_BROWSER=headless_firefox bin/rails test:system
  driven_by :selenium,
            using: ENV.fetch("SYSTEM_TEST_BROWSER", "headless_chrome").to_sym,
            screen_size: [ 1400, 1400 ]

  def login(user, password = "password")
    visit new_session_url
    fill_in "user[email_address]", with: user.email_address
    fill_in "user[password]", with: password
    click_on "Se connecter"
    assert_current_path root_path
  end
end
