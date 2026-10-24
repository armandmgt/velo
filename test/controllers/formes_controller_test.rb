require "test_helper"

class FormesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders the Forme chart with the 3-month window by default" do
    get forme_url

    assert_response :success
    assert_select "h1", text: "Forme"
    assert_select "[data-controller='forme-chart']"
    assert_select "a[aria-current='page']", text: "3 mois"
    assert_select "p", text: /Les activités sans fréquence cardiaque ne sont pas comptées/
  end

  test "switches window" do
    get forme_url(window: "1y")

    assert_response :success
    assert_select "a[aria-current='page']", text: "1 an"
    data = JSON.parse(css_select("[data-controller='forme-chart']").first["data-forme-chart-data-value"])
    assert_operator data["labels"].size, :>=, 365
  end

  test "hints at setting a max HR when it is missing" do
    get forme_url
    assert_select "a[href='#{user_path}']", text: "votre profil"

    @user.update_columns(max_heart_rate: 190)
    get forme_url
    assert_select "a[href='#{user_path}']", text: "votre profil", count: 0
  end

  test "requires authentication" do
    sign_out
    get forme_url
    assert_redirected_to new_session_url
  end
end
