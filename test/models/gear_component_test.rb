require "test_helper"

class GearComponentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @bike = gears(:road_bike)
    @chain = @bike.components.create!(kind: "chain", installed_on: Date.new(2026, 3, 1), service_interval_km: 3000)
  end

  def ride(distance_km, at:, gear: @bike)
    @user.activities.create!(name: "Sortie", sport: "bike", gear: gear, start_time: at, end_time: at + 1.hour,
                             location: "Paris", active_time: "PT3600S", distance: distance_km * 1000)
  end

  test "counts only this bike's activities from its install date on" do
    ride 100, at: Time.utc(2026, 2, 28, 10)
    ride 200, at: Time.utc(2026, 3, 1, 8)
    ride 300, at: Time.utc(2026, 3, 15, 8)
    ride 400, at: Time.utc(2026, 3, 16, 8), gear: gears(:gravel_bike)
    ride 500, at: Time.utc(2026, 3, 17, 8), gear: nil

    assert_equal 500_000.0, @chain.distance
  end

  test "the install date is the rider's day, not UTC's" do
    ride 50, at: Time.utc(2026, 2, 28, 23, 30) # 00:30 in Paris on March 1st

    assert_equal 50_000.0, @chain.distance
  end

  test "ok below 90 %, warning from 90 %, overdue past 100 %" do
    ride 2690, at: Time.utc(2026, 3, 2)
    assert_equal :ok, @chain.status

    ride 10, at: Time.utc(2026, 3, 3)
    assert_equal :warning, @chain.status

    ride 300, at: Time.utc(2026, 3, 4)
    assert_equal :warning, @chain.status, "exactly at the interval is not yet past it"

    ride 1, at: Time.utc(2026, 3, 5)
    assert_equal :overdue, @chain.status
    assert @chain.overdue?
  end

  test "replacing retires the old one with its final distance and starts the new one at 0" do
    ride 1840, at: Time.utc(2026, 3, 2)

    fresh = travel_to(Time.utc(2026, 4, 1, 12)) { @chain.replace! }

    @chain.reload
    assert @chain.retired?
    assert_equal 1_840_000.0, @chain.distance
    assert_equal 0.0, fresh.distance
    assert_equal [ "chain", 3000, Date.new(2026, 4, 1) ], [ fresh.kind, fresh.service_interval_km, fresh.installed_on ]

    ride 20, at: Time.utc(2026, 4, 2)
    assert_equal 1_840_000.0, @chain.reload.distance, "the replaced component's history is frozen"
    assert_equal 20_000.0, fresh.distance
  end

  test "only a bike has components" do
    component = gears(:trail_shoes).components.new(kind: "chain", installed_on: Date.current, service_interval_km: 100)

    assert_not component.valid?
    assert component.errors.include?(:gear)
  end

  test "a custom component needs a name" do
    component = @bike.components.new(kind: "custom", installed_on: Date.current, service_interval_km: 100)
    assert_not component.valid?

    component.nickname = "Roulements"
    assert component.valid?
    assert_equal "Roulements", component.name
  end

  test "the user's overdue components are those of active bikes past their interval" do
    ride 3001, at: Time.utc(2026, 3, 2)
    @bike.components.create!(kind: "tires", installed_on: Date.new(2026, 3, 1), service_interval_km: 5000)
    gears(:gravel_bike).components.create!(kind: "chain", installed_on: Date.new(2026, 1, 1), service_interval_km: 1)

    assert_equal [ @chain ], @user.overdue_gear_components

    @bike.retire!
    assert_empty @user.overdue_gear_components
  end
end
