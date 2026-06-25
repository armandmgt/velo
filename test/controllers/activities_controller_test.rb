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

  # The native recorder uploads multipart/form-data (the GPX file) while asking
  # for JSON back via the Accept header — not a JSON-encoded body.
  test "JSON create returns the activity id and url with a 201 and Location header" do
    assert_difference("Activity.count") do
      post activities_url,
           params: { activity: { sport: "bike", fit_file: file_fixture_upload("gpx/native_recording.gpx") } },
           headers: { "Accept" => "application/json" }
    end

    assert_response :created
    created = Activity.last
    body = response.parsed_body
    assert_equal created.id, body["id"]
    assert_equal activity_url(created), body["url"]
    assert_equal activity_url(created), response.headers["Location"]
  end

  test "JSON create returns 422 with errors when the activity is invalid" do
    assert_no_difference("Activity.count") do
      post activities_url,
           params: { activity: { fit_file: file_fixture_upload("gpx/empty.gpx") } },
           headers: { "Accept" => "application/json" }
    end

    assert_response :unprocessable_content
    assert response.parsed_body["errors"].present?
  end

  test "should show activity" do
    get activity_url(@activity)
    assert_response :success
  end

  test "renders the heart rate zones partial when the user has a max HR and the activity has HR samples" do
    users(:one).update!(max_heart_rate: 200)
    t = Time.zone.parse("2026-01-01 10:00:00")
    [ 110, 130, 150, 170, 190 ].each_with_index do |hr, i|
      @activity.activity_data_points.create!(recorded_at: t + i.seconds, heart_rate: hr)
    end

    get activity_url(@activity)

    assert_response :success
    assert_select "h3", text: I18n.t("activity.heart_rate_zone.title")
    assert_select "th", text: I18n.t("activity.heart_rate_zone.zone")
    assert_select "td", text: I18n.t("activity.heart_rate_zone.z1")
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
          params: { from: "name_prompt", activity: { name: "Sortie nommée" } },
          as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", @response.body
    assert_match "navbar_name_prompts", @response.body
    assert_match "dashboard_name_prompts", @response.body
    refute activity.reload.name_pending
  end

  test "update from edit page redirects to show" do
    activity = activities(:one)
    patch activity_url(activity),
          params: { activity: { name: "Renommée depuis l'edit" } },
          as: :turbo_stream

    assert_redirected_to activity_url(activity)
    assert_equal "Renommée depuis l'edit", activity.reload.name
  end

  test "update_visibility updates only visibility and does not clear name_pending" do
    activity = activities(:awaiting_name)
    original_name = activity.name
    patch visibility_activity_url(activity), params: { activity: { visibility: "shareable" } }

    assert_redirected_to activity_url(activity)
    activity.reload
    assert_equal "shareable", activity.visibility
    assert activity.name_pending, "name_pending should remain set"
    assert_equal original_name, activity.name
  end

  test "should destroy activity" do
    assert_difference("Activity.count", -1) do
      delete activity_url(@activity)
    end

    assert_redirected_to activities_url
  end
end
