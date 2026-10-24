require "application_system_test_case"

class HeatmapsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    start = Time.zone.local(2025, 5, 1, 9)
    [ [ "bike", "LINESTRING(2.34 48.85, 2.35 48.86)" ], [ "run", "LINESTRING(4.83 45.76, 4.84 45.77)" ] ].each do |sport, line|
      @user.activities.create!(name: "Sortie", sport:, start_time: start, end_time: start + 1.hour,
                               location: "Paris", active_time: "PT3600S", path: "SRID=4326;#{line}")
    end
  end

  test "the heatmap is reachable from the navigation and filters the rider's paths" do
    login(@user)
    find(".navbar [role=button].avatar").click
    click_on "Carte de chaleur"

    assert_selector "h1", text: "Carte de chaleur"
    assert_selector "#heatmap_map canvas.maplibregl-canvas", wait: 15
    assert_text "2 activités"

    select "Course", from: "sport"
    assert_text "1 activité"
    assert_current_path "/heatmap?sport=running&period="
    assert_selector "#heatmap_map[data-heatmap-tiles-url-value*='sport=running'] canvas.maplibregl-canvas"

    select "Personnalisée", from: "period"
    assert_selector "input[name=from]"
    fill_in "from", with: "2026-01-01"
    assert_text "Aucune activité ne correspond à ces filtres."
  end
end
