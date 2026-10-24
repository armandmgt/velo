require "test_helper"

class GearsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login(users(:one))
    @gear = gears(:road_bike)
  end

  test "index lists active gear and groups retired gear under Retiré" do
    get gears_url

    assert_response :success
    assert_select "#active_gears", text: /Vélo de course/
    assert_select "#active_gears", text: /Vieux biclou/, count: 0
    assert_select "#retired_gears h2", "Retiré"
    assert_select "#retired_gears", text: /Vieux biclou/
    assert_no_match "Vélo de Two", response.body
  end

  test "creates a bike that is the default for road bike" do
    assert_difference("Gear.count") do
      post gears_url, params: { gear: { kind: "bike", name: "Tarmac", brand: "Specialized", default_sports: [ "", "bike" ] } }
    end

    gear = Gear.last
    assert_redirected_to gear_url(gear)
    assert_equal users(:one), gear.user
    assert_equal gear, users(:one).default_gear_for("bike")
  end

  test "creates shoes with a photo" do
    post gears_url, params: { gear: { kind: "shoes", name: "Pegasus", photo: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png") } }

    assert Gear.last.shoes?
    assert Gear.last.photo.attached?
  end

  test "rejects gear without a name" do
    assert_no_difference("Gear.count") do
      post gears_url, params: { gear: { kind: "bike", name: "" } }
    end

    assert_response :unprocessable_content
  end

  test "show displays totals and component progress" do
    activities(:this_week_ride).update!(gear: @gear)
    @gear.components.create!(kind: "chain", installed_on: 1.year.ago.to_date, service_interval_km: 3000)

    get gear_url(@gear)

    assert_response :success
    assert_select "#gear_totals", text: /30 km/
    assert_select "#gear_components", text: "Chaîne — 30 / #{ActiveSupport::NumberHelper.number_to_delimited(3000)} km"
  end

  test "updates defaults" do
    patch gear_url(@gear), params: { gear: { name: "Renommé", default_sports: [ "", "gravel_ride" ] } }

    assert_redirected_to gear_url(@gear)
    assert_equal "Renommé", @gear.reload.name
    assert_equal %w[gravel_ride], @gear.default_sports
  end

  test "retiring keeps the activity assignment and stops the default" do
    @gear.update!(default_sports: %w[bike])
    activities(:this_week_ride).update!(gear: @gear)

    patch retire_gear_url(@gear)

    assert_redirected_to gear_url(@gear)
    assert @gear.reload.retired?
    assert_equal @gear, activities(:this_week_ride).reload.gear
    assert_nil users(:one).default_gear_for("bike")
  end

  test "reactivates retired gear" do
    patch reactivate_gear_url(gears(:retired_bike))

    assert_not gears(:retired_bike).reload.retired?
  end

  test "destroying unassigns its activities" do
    activities(:this_week_ride).update!(gear: @gear)

    assert_no_difference("Activity.count") do
      assert_difference("Gear.count", -1) { delete gear_url(@gear) }
    end

    assert_redirected_to gears_url
    assert_nil activities(:this_week_ride).reload.gear
  end

  test "the delete button asks for confirmation" do
    get gear_url(@gear)

    assert_select "form[action='#{gear_path(@gear)}'] button[data-turbo-confirm]"
  end

  test "another user's gear is out of reach" do
    get gear_url(gears(:other_users_bike))
    assert_response :not_found

    delete gear_url(gears(:other_users_bike))
    assert_response :not_found
  end
end
