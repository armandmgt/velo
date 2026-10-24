require "application_system_test_case"
require_relative "../test_helpers/synthetic_track"

class BestEffortsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
  end

  def run_5k(name, minutes, on:)
    gpx = SyntheticTrack.new(start: on).move(5_050, speed: 5_000.0 / (minutes * 60), every: 250).to_gpx
    activity = @user.activities.build(name:, sport: :run)
    ActivityIngestion.call(activity, StringIO.new(gpx), filename: "run.gpx", reverse_geocode: false)
    activity.save!
    activity
  end

  # Vertices of the map's best-effort highlight, as the map controller exposes
  # it on its element — set even while the style is still loading, which it
  # never finishes without a MapTiler key.
  def highlighted_vertices(activity)
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.getElementById("map_activity_#{activity.id}")
        const stretch = element?.dataset.highlightedStretch
        if (!stretch) return 0
        const [start, end] = stretch.split("-").map(Number)
        return end - start + 1
      })()
    JS
  end

  test "highlighting, removing and restoring an effort" do
    slower = run_5k("Footing tranquille", 25, on: Time.utc(2026, 1, 1, 8))
    faster = run_5k("Course glitchée", 20, on: Time.utc(2026, 2, 1, 8))
    login(@user)

    visit activity_url(faster)
    within "#best_efforts_activity_#{faster.id}" do
      assert_text(/meilleurs efforts/i)
      effort = find("#best_effort_#{faster.best_efforts.find_by!(distance: '5k').id}")
      assert_text "20:00"
      assert_selector "span", text: "PR"

      effort.find("button[aria-pressed]").click
      assert_selector "button[aria-pressed=true]", count: 1
      effort_5k = faster.best_efforts.find_by!(distance: "5k")
      assert_equal effort_5k.end_index - effort_5k.start_index + 1, highlighted_vertices(faster)

      accept_confirm { effort.click_on "Retirer" }
      assert_selector "#best_effort_#{faster.best_efforts.find_by!(distance: '5k').id}", text: "Retiré"
    end

    visit records_url(category: "running")
    within "#records_5k" do
      assert_text slower.name
      assert_no_text faster.name
    end

    visit activity_url(faster)
    within "#best_effort_#{faster.best_efforts.find_by!(distance: '5k').id}" do
      click_on "Rétablir"
    end
    assert_no_text "Retiré"

    visit records_url(category: "running")
    within "#records_5k" do
      assert_text "20:00"
      assert_text faster.name
    end
  end
end
