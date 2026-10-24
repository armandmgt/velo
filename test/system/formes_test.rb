require "application_system_test_case"

class FormesTest < ApplicationSystemTestCase
  setup do
    user = users(:one)
    user.update_columns(max_heart_rate: 190)
    [ 3, 10, 20 ].each do |days_ago|
      start = days_ago.days.ago
      user.activities.create!(name: "Sortie", sport: :bike, start_time: start, end_time: start + 1.hour,
                              location: "Paris", active_time: "PT3600S", effort_score: 80, effort_score_source: :heart_rate)
    end
  end

  test "charts fitness, fatigue and form and switches windows" do
    login(users(:one))

    find(".navbar .dropdown [role='button']").click
    click_on "Forme"
    assert_selector "h1", text: "Forme"
    assert_selector "a[aria-current='page']", text: "3 mois"
    assert_text(/condition/i)
    assert_text "Les activités sans fréquence cardiaque ne sont pas comptées."
    assert_chart_drawn

    click_on "1 an"
    assert_selector "a[aria-current='page']", text: "1 an"
    assert_chart_drawn
  end

  private

  # Chart.js sizes the canvas itself once it has drawn.
  def assert_chart_drawn
    assert_selector "canvas[data-forme-chart-target='canvas'][style*='box-sizing']", visible: :all
    painted = page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector("[data-forme-chart-target='canvas']")
        const pixels = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data
        return pixels.some(value => value !== 0)
      })()
    JS
    assert painted, "expected the Forme chart to be drawn"
  end
end
