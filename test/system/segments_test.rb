require "application_system_test_case"
require_relative "../test_helpers/segment_track_helper"

class SegmentsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @wait = Capybara.default_max_wait_time
    Capybara.default_max_wait_time = 15
    @user = users(:one)
    @user.update!(map_hide_start_end_distance: 0)
    @activity = ingest_points(@user, points_at(ride(0, 2_000)), name: "Footing du parc")
  end

  teardown { Capybara.default_max_wait_time = @wait }

  def choose(start_index, end_index)
    page.execute_script(<<~JS, start_index, end_index)
      const [ start, end ] = arguments
      const set = (name, value) => {
        const input = document.querySelector(`input[name="segment[${name}]"]`)
        input.value = value
        input.dispatchEvent(new Event("input", { bubbles: true }))
      }
      set("end_index", end)
      set("start_index", start)
    JS
  end

  test "creating a segment from the activity page and seeing its leaderboard" do
    login(@user)
    visit activity_url(@activity)
    click_on "Créer un segment"
    assert_selector "h1", text: "Créer un segment"

    choose(50, 60)
    assert_text "100 m"
    assert_button "Créer le segment", disabled: true

    choose(50, 120)
    assert_text "700 m"
    fill_in "Nom du segment", with: "Ligne droite du parc"
    click_on "Créer le segment"

    assert_selector "h1", text: "Ligne droite du parc"
    assert_text "Vous n'avez pas encore parcouru ce segment."

    perform_enqueued_jobs(only: BackfillSegmentEffortsJob)
    visit current_url
    within("section[id^=own_efforts_segment]") { assert_text "1:10" }
    within("section[id^=leaderboard_segment]") { assert_text(/vous/i) }

    visit activity_url(@activity)
    within("#segment_efforts_activity_#{@activity.id}") { assert_text "Ligne droite du parc" }
  end
end
