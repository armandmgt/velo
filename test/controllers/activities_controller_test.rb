require "test_helper"

class ActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @activity = activities(:one)
    login(users(:one))
  end

  test "should get index" do
    get activities_url
    assert_response :success
  end

  test "should get new" do
    get new_activity_url
    assert_response :success
  end

  test "should create activity" do
    assert_difference("Activity.count") do
      post activities_url, params: { activity: { description: @activity.description, name: @activity.name, sport: @activity.sport, fit_file: file_fixture_upload("fit/bike.fit") } }
    end

    assert_redirected_to activity_url(Activity.last)
  end

  test "should create activity from a GPX upload" do
    assert_difference("Activity.count") do
      post activities_url, params: { activity: { name: "GPX upload", sport: "bike", fit_file: file_fixture_upload("gpx/ride.gpx") } }
    end

    assert_redirected_to activity_url(Activity.last)
    assert_operator Activity.last.distance.to_f, :>, 0
  end

  test "should show activity" do
    get activity_url(@activity)
    assert_response :success
  end

  test "should get edit" do
    get edit_activity_url(@activity)
    assert_response :success
  end

  test "should update activity" do
    patch activity_url(@activity), params: { activity: { description: @activity.description, name: @activity.name, sport: @activity.sport } }
    assert_redirected_to activity_url(@activity)
  end

  test "updating the name clears the name_pending flag" do
    activity = activities(:awaiting_name)
    patch activity_url(activity), params: { activity: { name: "Sortie nommée" } }
    assert_redirected_to activity_url(activity)
    refute activity.reload.name_pending
    assert_equal "Sortie nommée", activity.name
  end

  test "inline rename responds with turbo_stream replacing the prompt containers" do
    activity = activities(:awaiting_name)
    patch activity_url(activity),
          params: { activity: { name: "Sortie nommée" } },
          as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", @response.body
    assert_match "navbar_name_prompts", @response.body
    assert_match "dashboard_name_prompts", @response.body
    refute activity.reload.name_pending
  end

  test "should destroy activity" do
    assert_difference("Activity.count", -1) do
      delete activity_url(@activity)
    end

    assert_redirected_to activities_url
  end
end
