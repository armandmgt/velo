require "test_helper"

class RecordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login(users(:one))
    activities(:one).best_efforts.create!(distance: "10k", elapsed_seconds: 1_080, start_index: 0, end_index: 1)
  end

  test "shows the cycling records by default" do
    get records_url

    assert_response :success
    assert_select "#records_10k", text: /18:00/
    assert_select "#records_10k", text: /33.3 km\/h/
    assert_match "Plus longue sortie", response.body
  end

  test "switches category and ignores an unknown year" do
    get records_url(category: "running", year: 1999)

    assert_response :success
    assert_select "#records_marathon", text: /Aucun effort/
    assert_no_match "Plus longue sortie", response.body
  end

  test "filters to a year" do
    get records_url(category: "cycling", year: 2019)
    assert_select "#records_10k", text: /18:00/

    get records_url(category: "cycling", year: activities(:this_week_ride).start_time.year)
    assert_select "#records_10k", text: /Aucun effort/
  end
end
