require "application_system_test_case"

# Guards the GPX wire format. Byte-equality against the same fixture
# `GpxExtractorTest` round-trips server-side, so both halves of the contract hang
# on one artifact.
class RecordingReviewTest < ApplicationSystemTestCase
  FIXTURE = Rails.root.join("test/fixtures/files/gpx/native_recording.gpx")

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

  # `import()` from an injected script doesn't go through the page's import map
  # in every browser, so resolve the specifier against it by hand.
  def encode_gpx(handoff, platform)
    page.evaluate_async_script(<<~JS, handoff, platform)
      const [handoff, platform, done] = [arguments[0], arguments[1], arguments[2]]
      const map = JSON.parse(document.querySelector('script[type="importmap"]').textContent)
      const url = new URL(map.imports["controllers/lib/gpx_encoder"], document.baseURI).href
      import(url)
        .then(({ encodeGpx }) => done(encodeGpx(handoff, platform)))
        .catch((error) => done(`ERROR: ${error}`))
    JS
  end

  test "the web GPX encoder reproduces the S0 contract fixture byte for byte" do
    login(users(:one))
    visit new_activity_url

    assert_equal FIXTURE.read, encode_gpx(handoff, "ios")
  end

  # `workout` has no `<trk><type>` mapping, so emitting one would have the
  # extractor fall back to `:bike`.
  test "a sport with no GPX mapping omits the track type" do
    login(users(:one))
    visit new_activity_url

    gpx = encode_gpx(handoff.merge("sport" => "workout"), "android")

    assert_no_match(/<type>/, gpx)
    assert_match(/creator="Velo Android"/, gpx)
  end
end
