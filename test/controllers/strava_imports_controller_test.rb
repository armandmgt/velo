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
    assert_select "h1", /Résultat de l'import/

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

  test "imports activities with names from activities.csv" do
    zip = fixture_file_upload(
      Rails.root.join("test/fixtures/files/exports/strava_export_44776215.zip"),
      "application/zip"
    )

    post strava_imports_path, params: { file: zip }

    # FIT files in the fixture have named activities in activities.csv (e.g. "Récup")
    assert @user.activities.reload.none? { |a| a.name == "Imported activity" },
      "Expected all imported activities to have names from activities.csv"
  end

  test "updates activity names on re-import" do
    zip = fixture_file_upload(
      Rails.root.join("test/fixtures/files/exports/strava_export_44776215.zip"),
      "application/zip"
    )

    post strava_imports_path, params: { file: zip }

    # "Récup" is the CSV name for activities/19271420703.fit.gz
    activity = @user.activities.reload.find_by!(name: "Récup")
    activity.update!(name: "Manually changed name")

    post strava_imports_path, params: { file: zip }

    assert_equal "Récup", activity.reload.name,
      "Expected re-import to restore the name from activities.csv"
  end
end
