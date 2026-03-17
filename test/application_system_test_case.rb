require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  def login(user, password = "password")
    visit new_session_url
    fill_in "user[email_address]", with: user.email_address
    fill_in "user[password]", with: password
    click_on "Se connecter"
    assert_current_path root_path
  end
end
