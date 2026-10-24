require "test_helper"

class GearComponentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login(users(:one))
    @bike = gears(:road_bike)
    @chain = @bike.components.create!(kind: "chain", installed_on: Date.new(2026, 1, 1), service_interval_km: 3000)
  end

  test "adds a component to a bike" do
    assert_difference("@bike.components.count") do
      post gear_components_url(@bike), params: { gear_component: { kind: "tires", installed_on: "2026-05-01", service_interval_km: 4000 } }
    end

    assert_redirected_to gear_url(@bike)
  end

  test "shoes have no components" do
    get new_gear_component_url(gears(:trail_shoes))

    assert_response :not_found
  end

  test "replacing retires the old component and installs a fresh one" do
    activities(:this_week_ride).update!(gear: @bike)

    assert_difference("@bike.components.count") { post replace_gear_component_url(@bike, @chain) }

    assert_redirected_to gear_url(@bike)
    assert @chain.reload.retired?
    assert_equal activities(:this_week_ride).distance.to_f, @chain.distance
    assert_equal 0, @bike.components.active.sole.distance
  end

  test "a retired component can't be replaced again" do
    @chain.replace!

    post replace_gear_component_url(@bike, @chain)

    assert_response :not_found
  end

  test "updates the service interval" do
    patch gear_component_url(@bike, @chain), params: { gear_component: { service_interval_km: 2500 } }

    assert_redirected_to gear_url(@bike)
    assert_equal 2500, @chain.reload.service_interval_km
  end

  test "rejects a zero interval" do
    patch gear_component_url(@bike, @chain), params: { gear_component: { service_interval_km: 0 } }

    assert_response :unprocessable_content
  end

  test "another user's bike is out of reach" do
    post gear_components_url(gears(:other_users_bike)), params: { gear_component: { kind: "chain", installed_on: "2026-01-01", service_interval_km: 1 } }

    assert_response :not_found
  end
end
