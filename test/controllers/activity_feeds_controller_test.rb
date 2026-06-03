require "test_helper"

class ActivityFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login(users(:one))
  end

  test "should get dashboard" do
    get root_url
    assert_response :success
  end

  test "dashboard not accessible without login" do
    delete session_path
    get root_url
    assert_redirected_to new_session_path
  end

  test "this year section shows all the user activities" do
    get root_url
    assert_select "div.stat-value", text: "4"
  end

  test "this year total distance includes all activities" do
    get root_url
    # 30km + 10km + 120km + 25km = 185.0 km
    assert_select "div.stat-value", text: "185.0 km"
  end

  test "cycling personal record shows the longest bike ride name" do
    get root_url
    assert_select "a", text: activities(:older_ride).name
  end

  test "running personal record shows the run name" do
    get root_url
    assert_select "a", text: activities(:this_month_run).name
  end

  test "recent activities section is present" do
    get root_url
    assert_select "h2", text: "Activités récentes"
  end

  test "does not show other users activities" do
    get root_url
    assert_select "a", text: activities(:two).name, count: 0
  end
end
