require "test_helper"

class GearTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @road = gears(:road_bike)
    @gravel = gears(:gravel_bike)
  end

  test "maps a sport to the kind of gear it is done with" do
    assert_equal "bike", Gear.kind_for_sport("gravel_ride")
    assert_equal "shoes", Gear.kind_for_sport("trail_run")
    assert_nil Gear.kind_for_sport("swim")
    assert_nil Gear.kind_for_sport(nil)
  end

  test "becomes the default for the sports it is marked for" do
    @road.update!(default_sports: %w[bike virtual_ride])

    assert_equal %w[bike virtual_ride], @road.reload.default_sports.sort
    assert_equal @road, @user.default_gear_for("bike")
    assert_nil @user.default_gear_for("gravel_ride")
  end

  test "a sport has one default: marking another gear takes the sport over" do
    @road.update!(default_sports: %w[bike gravel_ride])
    @gravel.update!(default_sports: %w[gravel_ride])

    assert_equal %w[bike], @road.reload.default_sports
    assert_equal @gravel, @user.default_gear_for("gravel_ride")
    assert_equal 1, @user.gear_defaults.where(sport: "gravel_ride").count
  end

  test "the database refuses two defaults for the same sport" do
    @road.update!(default_sports: %w[bike])

    assert_raises(ActiveRecord::RecordNotUnique) do
      GearDefault.create!(user: @user, gear: @gravel, sport: "bike")
    end
  end

  test "ignores default sports outside its kind" do
    gears(:trail_shoes).update!(default_sports: %w[trail_run bike swim])

    assert_equal %w[trail_run], gears(:trail_shoes).reload.default_sports
  end

  test "unticking every sport clears its defaults" do
    @road.update!(default_sports: %w[bike])
    @road.update!(default_sports: [ "" ])

    assert_empty @road.reload.default_sports
  end

  test "other users' defaults are untouched" do
    gears(:other_users_bike).update!(default_sports: %w[bike])
    @road.update!(default_sports: %w[bike])

    assert_equal gears(:other_users_bike), users(:two).default_gear_for("bike")
  end

  test "retiring keeps its activities and totals but drops its defaults" do
    @road.update!(default_sports: %w[bike])
    activities(:this_week_ride).update!(gear: @road)
    totals = @road.totals

    @road.retire!

    assert @road.retired?
    assert_nil @user.default_gear_for("bike")
    assert_equal @road, activities(:this_week_ride).reload.gear
    assert_equal totals, @road.totals
  end

  test "retired gear can't be made a default" do
    gears(:retired_bike).update!(default_sports: %w[bike])

    assert_nil @user.default_gear_for("bike")
  end

  test "reactivating brings it back as a choice, without its old defaults" do
    retired = gears(:retired_bike)
    retired.reactivate!

    assert_includes @user.gears.active, retired
    assert_empty retired.default_sports
  end

  test "deleting unassigns its activities without deleting them" do
    activity = activities(:this_week_ride)
    activity.update!(gear: @road)

    assert_no_difference("Activity.count") { @road.destroy! }

    assert_nil activity.reload.gear
  end

  test "totals sum distance, moving time, elevation and count of its activities" do
    activities(:this_week_ride).update!(gear: @road)
    activities(:older_ride).update!(gear: @road)

    totals = @road.totals

    assert_equal 150_000.0, totals.distance
    assert_equal 3600 + 14_400, totals.moving_seconds
    assert_equal 1800.0, totals.elevation
    assert_equal 2, totals.count
  end

  test "kind can't change once created" do
    assert_raises(ActiveRecord::ActiveRecordError) { @road.update!(kind: "shoes") }
  end
end
