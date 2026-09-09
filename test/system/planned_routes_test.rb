require "application_system_test_case"

class PlannedRoutesTest < ApplicationSystemTestCase
  test "the route planner's map initialises" do
    login(users(:one))
    visit new_planned_route_url

    assert_selector "canvas.maplibregl-canvas", wait: 15
  end
end
