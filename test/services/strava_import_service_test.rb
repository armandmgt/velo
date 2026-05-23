require "test_helper"

class StravaImportServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @zip_path = Rails.root.join("test/fixtures/files/exports/strava_one_activity.zip")
  end

  test "imports activity with name from activities.csv" do
    call_service
    assert @user.activities.exists?(name: "Récup"), "Expected activity named 'Récup' to be imported"
  end

  test "maps Ride sport type to bike" do
    call_service
    assert @user.activities.exists?(name: "Récup", sport: "bike")
  end

  test "returns imported count" do
    result = call_service
    assert_equal 1, result[:imported]
    assert_equal 0, result[:skipped]
    assert_equal 0, result[:failed]
  end

  test "skips duplicate on second import" do
    call_service
    result = call_service
    assert_equal 0, result[:imported]
    assert_equal 1, result[:skipped]
  end

  test "updates activity name on re-import" do
    call_service
    activity = @user.activities.find_by!(name: "Récup")
    activity.update!(name: "Changed")

    call_service

    assert_equal "Récup", activity.reload.name
  end

  test "imports a GPX activity with name and sport from activities.csv" do
    result = call_service(gpx_zip_path)
    assert_equal 1, result[:imported]
    activity = @user.activities.find_by!(name: "Sortie GPX")
    assert_equal "bike", activity.sport
    assert_operator activity.distance.to_f, :>, 0
    assert_equal 5, activity.activity_data_points.count
  end

  test "dedups GPX activity on re-import" do
    call_service(gpx_zip_path)
    result = call_service(gpx_zip_path)
    assert_equal 0, result[:imported]
    assert_equal 1, result[:skipped]
  end

  private

  def gpx_zip_path
    Rails.root.join("test/fixtures/files/exports/strava_gpx_activity.zip")
  end

  def call_service(path = @zip_path)
    file = Rack::Test::UploadedFile.new(path, "application/zip")
    StravaImportService.new(@user, file).call
  end
end
