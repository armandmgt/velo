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

  test "year period shows the count of this year's activities" do
    get root_url
    # this_week_ride + this_month_run + older_ride + awaiting_name = 4
    # (the 2019 "one" ride is not in the current year)
    assert_select "[data-period=?]", "year" do
      assert_select "div", text: "4"
    end
  end

  test "year period total distance includes all this year's activities" do
    get root_url
    # 30km + 10km + 120km + 25km = 185 km (distance_km is rounded to an integer)
    assert_select "[data-period=?]", "year" do
      assert_select "span", text: "185km"
    end
  end

  test "cycling personal record links to the longest bike ride" do
    get root_url
    assert_select "[data-dashboard-tabs-target=records] a[href=?]",
                  activity_path(activities(:older_ride))
  end

  test "running personal record links to the run" do
    get root_url
    assert_select "[data-dashboard-tabs-target=records] a[href=?]",
                  activity_path(activities(:this_month_run))
  end

  test "recent activities section is present" do
    get root_url
    assert_select "h3", text: "Activités récentes"
  end

  test "does not show other users activities" do
    get root_url
    assert_select "a", text: activities(:two).name, count: 0
  end

  test "lists components past their interval, linking to the bike" do
    bike = gears(:road_bike)
    activities(:this_week_ride).update!(gear: bike)
    bike.components.create!(kind: "chain", installed_on: 1.year.ago.to_date, service_interval_km: 10)

    get root_url

    assert_select "#dashboard_due_components a[href='#{gear_path(bike)}']", text: /Chaîne/
  end

  test "shows no maintenance card when nothing is due" do
    get root_url

    assert_select "#dashboard_due_components", count: 0
  end
end
