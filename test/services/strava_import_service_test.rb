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

  test "does not flag activity as name_pending when the CSV provides a name" do
    call_service
    refute @user.activities.find_by!(name: "Récup").name_pending
  end

  test "flags activity as name_pending when the CSV name is blank" do
    result = call_service(blank_name_zip_path)
    assert_equal 1, result[:imported]
    activity = @user.activities.find_by!(name: "Sortie importée")
    assert activity.name_pending, "expected the auto-named activity to await a real name"
  ensure
    File.delete(blank_name_zip_path) if File.exist?(blank_name_zip_path)
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

  test "retains the FIT source file so the activity can be re-imported" do
    call_service
    activity = @user.activities.find_by!(name: "Récup")
    assert activity.source_file.attached?, "expected the source file to be retained"
    assert activity.source_file.filename.to_s.downcase.end_with?(".fit")
  end

  test "retains the GPX source file so the activity can be re-imported" do
    call_service(gpx_zip_path)
    activity = @user.activities.find_by!(name: "Sortie GPX")
    assert activity.source_file.attached?, "expected the source file to be retained"
    assert activity.source_file.filename.to_s.downcase.end_with?(".gpx")
  end

  private

  def gpx_zip_path
    Rails.root.join("test/fixtures/files/exports/strava_gpx_activity.zip")
  end

  # Builds a Strava-style export whose activities.csv has a blank "Activity Name",
  # so the import falls back to "Sortie importée" and should be flagged pending.
  def blank_name_zip_path
    @blank_name_zip_path ||= begin
      path = Rails.root.join("tmp/strava_blank_name_#{SecureRandom.hex(4)}.zip")
      fit_bytes = File.binread(Rails.root.join("test/fixtures/files/fit/bike.fit"))
      Zip::File.open(path.to_s, create: true) do |zip|
        zip.get_output_stream("activities/blank.fit") { |io| io.write(fit_bytes) }
        zip.get_output_stream("activities.csv") do |io|
          io.write("Activity ID,Activity Name,Activity Type,Filename\n")
          io.write("1,,Ride,activities/blank.fit\n")
        end
      end
      path.to_s
    end
  end

  def call_service(path = @zip_path)
    file = Rack::Test::UploadedFile.new(path, "application/zip")
    StravaImportService.new(@user, file).call
  end
end
