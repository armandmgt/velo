require "test_helper"

class StravaImportServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @zip_path = Rails.root.join("test/fixtures/files/exports/strava_one_activity.zip")
  end

  teardown do
    Array(@gear_zips).each { |path| File.delete(path) if File.exist?(path) }
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

  test "creates the gear an activities.csv names and assigns it" do
    result = call_service(gear_zip_path([ [ "Ride", "Tarmac SL7" ], [ "Run", "Pegasus 40" ] ]))

    assert_equal 2, result[:imported]
    bike = @user.gears.find_by!(name: "Tarmac SL7")
    shoes = @user.gears.find_by!(name: "Pegasus 40")
    assert_equal [ "bike", "shoes" ], [ bike.kind, shoes.kind ]
    assert_equal [ bike ], bike.activities.to_a.map(&:gear)
    assert_equal "run", shoes.activities.sole.sport
  end

  test "assigns existing gear of the same name, retired gear included" do
    retired = gears(:retired_bike)

    assert_no_difference("Gear.count") { call_service(gear_zip_path([ [ "Ride", retired.name ] ])) }

    assert_equal 1, retired.activities.count
  end

  test "names the same gear once across many activities" do
    assert_difference("Gear.count", 1) do
      call_service(gear_zip_path([ [ "Ride", "Tarmac SL7" ], [ "Gravel Ride", "Tarmac SL7" ] ]))
    end
  end

  test "leaves gear named on a sport without gear unassigned" do
    assert_no_difference("Gear.count") { call_service(gear_zip_path([ [ "Swim", "Bonnet" ] ])) }

    assert_nil @user.activities.find_by!(sport: "swim").gear
  end

  test "an activity with a blank gear cell gets its sport's default" do
    gears(:road_bike).update!(default_sports: %w[bike])

    call_service(gear_zip_path([ [ "Ride", "" ] ]))

    assert_equal gears(:road_bike), @user.activities.find_by!(name: "Activité 1").gear
  end

  test "an archive without a gear column imports as before, with the sport's default" do
    gears(:road_bike).update!(default_sports: %w[bike])

    assert_no_difference("Gear.count") do
      result = call_service
      assert_equal 1, result[:imported]
    end

    assert_equal gears(:road_bike), @user.activities.find_by!(name: "Récup").gear
  end

  test "re-importing an archive that names gear assigns it to the already imported activity" do
    call_service(gear_zip_path([ [ "Ride", "" ] ]))
    activity = @user.activities.find_by!(name: "Activité 1")
    assert_nil activity.gear

    result = call_service(gear_zip_path([ [ "Ride", "Tarmac SL7" ] ]))

    assert_equal 1, result[:skipped]
    assert_equal "Tarmac SL7", activity.reload.gear.name
  end

  private

  # One GPX activity per [Strava type, gear name] row, a day apart so none
  # dedupes against another.
  def gear_zip_path(rows)
    path = Rails.root.join("tmp/strava_gear_#{SecureRandom.hex(4)}.zip")
    Zip::File.open(path.to_s, create: true) do |zip|
      zip.get_output_stream("activities.csv") do |io|
        io.write("Activity ID,Activity Name,Activity Type,Activity Gear,Filename\n")
        rows.each.with_index(1) do |(type, gear), index|
          io.write(%(#{index},Activité #{index},#{type},"#{gear}",activities/#{index}.gpx\n))
        end
      end
      rows.each_index do |index|
        zip.get_output_stream("activities/#{index + 1}.gpx") { |io| io.write(gpx_starting_at(Time.utc(2026, 6, 1, 8) - index.days)) }
      end
    end
    @gear_zips = [ *@gear_zips, path ]
    path.to_s
  end

  def gpx_starting_at(time)
    points = 3.times.map do |i|
      %(<trkpt lat="#{48.85 + i * 0.001}" lon="2.35"><time>#{(time + i * 10).utc.iso8601}</time></trkpt>)
    end
    %(<?xml version="1.0"?><gpx><trk><trkseg>#{points.join}</trkseg></trk></gpx>)
  end

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
