require "test_helper"

class StravaImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders new" do
    get new_strava_import_path
    assert_response :success
  end

  test "redirects with alert when no zip is provided" do
    post strava_imports_path

    assert_redirected_to new_strava_import_path
    assert_equal "Please upload a ZIP file", flash[:alert]
  end

  test "imports activities from zip" do
    zip = fixture_file_upload(
      Rails.root.join("test/fixtures/files/exports/strava_export_44776215.zip"),
      "application/zip"
    )

    before_count = @user.activities.count

    post strava_imports_path, params: { file: zip }

    assert_response :success
    assert_select "h1", /Import result/

    after_count = @user.activities.count

    assert after_count > before_count, "Expected activities to be imported"
  end

  test "skips duplicates on second import" do
    zip = fixture_file_upload(
      Rails.root.join("test/fixtures/files/exports/strava_export_44776215.zip"),
      "application/zip"
    )

    post strava_imports_path, params: { file: zip }
    first_count = @user.activities.count

    post strava_imports_path, params: { file: zip }
    second_count = @user.activities.count

    assert_equal first_count, second_count, "Expected duplicates to be skipped"
  end
end
