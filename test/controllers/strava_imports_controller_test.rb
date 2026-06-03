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
    assert_equal "Veuillez téléverser un fichier ZIP.", flash[:alert]
  end

  test "imports activities from zip and renders result" do
    zip = fixture_file_upload(
      Rails.root.join("test/fixtures/files/exports/strava_one_activity.zip"),
      "application/zip"
    )

    before_count = @user.activities.count
    post strava_imports_path, params: { file: zip }

    assert_response :success
    assert_select "h1", /Résultat de l'import/
    assert @user.activities.count > before_count, "Expected activities to be imported"
  end
end
