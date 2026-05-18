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

  private

  def call_service
    file = Rack::Test::UploadedFile.new(@zip_path, "application/zip")
    StravaImportService.new(@user, file).call
  end
end
