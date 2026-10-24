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
  test "cycling records show the power curve and power podiums for riders with power" do
    activities(:one).update_columns(power_curve: { "5" => 900, "1200" => 280 })
    activities(:one).best_efforts.create!(distance: "power_20m", elapsed_seconds: 1_200, average_power: 280)

    get records_url(category: "cycling", curve_period: "this_year")

    assert_select "#power_curve[data-power-curve-chart-data-value*='\"x\":1200']"
    assert_select "#power_curve select[name=curve_period] option[selected][value=this_year]"
    assert_select "#records_power_20m", text: /280 W/
    assert_select "#records_power_20m .badge", text: "PR"
  end

  test "no power section without power data, nor on the running tab" do
    get records_url(category: "cycling")
    assert_select "#power_records", count: 0

    activities(:one).update_columns(power_curve: { "5" => 900 })
    get records_url(category: "running")
    assert_select "#power_records", count: 0
  end
end
