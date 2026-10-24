require "application_system_test_case"
require_relative "../test_helpers/synthetic_track"

class PowerAnalysisTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  # Ingests a 1 Hz ride (8 m/s) from `[watts, seconds]` blocks.
  def ride(name, *blocks, on:)
    track = SyntheticTrack.new(start: on, power: blocks.first.first)
    blocks.each { |watts, seconds| track.move(seconds * 8.0, speed: 8.0, power: watts) }
    activity = @user.activities.build(name:, sport: :bike)
    ActivityIngestion.call(activity, StringIO.new(track.to_gpx(type: "cycling")), filename: "ride.gpx",
                           reverse_geocode: false)
    activity.save!
    activity
  end

  test "adopting the suggested FTP, then reading power on the activity and records pages" do
    ride("Sortie tranquille", [ 200, 1_500 ], on: 3.weeks.ago)
    hard = ride("Sortie au seuil", [ 200, 300 ], [ 300, 1_200 ], on: 1.week.ago)
    login(@user)

    visit user_url
    within "#profile-ftp" do
      assert_text "Estimation : 285 W"
      click_on "Utiliser"
      assert_field "user[ftp]", with: "285"
    end
    assert_nil @user.reload.ftp, "the suggestion is never saved on its own"
    click_on "Enregistrer", match: :first
    assert_text "Profil mis à jour."
    assert_equal 285, @user.reload.ftp

    perform_enqueued_jobs
    visit activity_url(hard)
    assert_text(/puissance pondérée\s+287 W/i)
    within "#best_efforts_activity_#{hard.id}" do
      within "#best_effort_#{hard.best_efforts.find_by!(distance: 'power_20m').id}" do
        assert_text "Puissance 20 min"
        assert_text "300 W"
        assert_selector ".badge", text: "PR"
      end
    end
    within "#power_zones" do
      # FTP 285: 200 W is endurance, 300 W (105 %) just tips into VO2max.
      assert_selector "tr", text: /Z2 · Endurance.*20%/m
      assert_selector "tr", text: /Z5 · VO2max.*80%/m
    end
    assert_selector "h3[title*='TSS']", text: /score d'effort/i

    visit records_url(category: "cycling")
    within "#records_power_20m" do
      assert_text "Sortie au seuil"
      assert_text "300 W"
    end
    assert_curve_drawn

    select "Cette année", from: "Comparer avec"
    assert_selector "#power_curve[data-power-curve-chart-labels-value*='Cette année']"
    assert_curve_drawn
  end

  private

  def perform_enqueued_jobs
    RecomputeEffortScoresJob.perform_now(@user)
  end

  # Chart.js sizes the canvas itself once it has drawn.
  def assert_curve_drawn
    assert_selector "canvas[data-power-curve-chart-target='canvas'][style*='box-sizing']", visible: :all
    painted = page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector("[data-power-curve-chart-target='canvas']")
        const pixels = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data
        return pixels.some(value => value !== 0)
      })()
    JS
    assert painted, "expected the power curve to be drawn"
  end
end
