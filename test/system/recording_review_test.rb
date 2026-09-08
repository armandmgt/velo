require "application_system_test_case"

# The GPX encoder used to exist twice, in Swift and Kotlin, and the Kotlin half
# carried the only unit test. #116 moved it into JavaScript
# (`controllers/lib/gpx_encoder`), so this is what now guards the S0 §2 wire
# format — the one place where a silent bug corrupts a rider's ride (ADR 0003).
#
# It asserts byte-equality with `test/fixtures/files/gpx/native_recording.gpx`,
# the same fixture `GpxExtractorTest` round-trips through the server, so the two
# halves of the contract are pinned to a single artifact.
class RecordingReviewTest < ApplicationSystemTestCase
  FIXTURE = Rails.root.join("test/fixtures/files/gpx/native_recording.gpx")

  # The handoff the shells send for the ride the fixture describes: ten 1 Hz
  # fixes climbing north, with heart rate, cadence and power on every point.
  def handoff
    points = 10.times.map do |index|
      {
        "t" => "2026-06-25T08:00:%02dZ" % index,
        "lat" => (48.8566 + index * 0.00005).round(7),
        "lon" => 2.3522,
        "ele" => 35.0 + index * 0.5,
        "hr" => 112 + index * 2,
        "cad" => [ 84, 85, 86, 87, 88, 89, 90, 89, 88, 87 ][index],
        "pw" => [ 180, 190, 200, 210, 220, 210, 200, 195, 190, 185 ][index]
      }
    end

    {
      "version" => 1,
      "recordingUuid" => "6f1b0f6e-0000-4000-8000-000000000000",
      "sport" => "bike",
      "startedAt" => "2026-06-25T08:00:00Z",
      "stats" => { "distance" => 50.0, "elapsed" => 9.0, "movingTime" => 9.0, "averageSpeed" => 5.5 },
      "laps" => [],
      "points" => points
    }
  end

  test "the web GPX encoder reproduces the S0 contract fixture byte for byte" do
    login(users(:one))
    visit new_activity_url

    gpx = page.evaluate_async_script(<<~JS, handoff)
      const handoff = arguments[0]
      const done = arguments[arguments.length - 1]
      import("controllers/lib/gpx_encoder")
        .then(({ encodeGpx }) => done(encodeGpx(handoff, "ios")))
        .catch((error) => done(`ERROR: ${error}`))
    JS

    assert_equal FIXTURE.read, gpx
  end

  # `workout` is the one sport with no `<trk><type>` mapping, so it must travel
  # via the `activity[sport]` param alone (S0 §3). Emitting a bogus type would
  # have the extractor fall back to `:bike`.
  test "a sport with no GPX mapping omits the track type" do
    login(users(:one))
    visit new_activity_url

    gpx = page.evaluate_async_script(<<~JS, handoff.merge("sport" => "workout"))
      const handoff = arguments[0]
      const done = arguments[arguments.length - 1]
      import("controllers/lib/gpx_encoder")
        .then(({ encodeGpx }) => done(encodeGpx(handoff, "android")))
        .catch((error) => done(`ERROR: ${error}`))
    JS

    assert_no_match(/<type>/, gpx)
    assert_match(/creator="Velo Android"/, gpx)
  end
end
