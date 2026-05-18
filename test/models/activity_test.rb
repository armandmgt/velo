require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "sport_icon_name does not raise for any sport value" do
    Activity.sports.each_key do |sport_key|
      activity = Activity.new(sport: sport_key)
      assert_nothing_raised { activity.sport_icon_name }
    end
  end

  test "sport_category returns correct category" do
    assert_equal :cycling, Activity.new(sport: "bike").sport_category
    assert_equal :cycling, Activity.new(sport: "e_bike_ride").sport_category
    assert_equal :running, Activity.new(sport: "trail_run").sport_category
    assert_equal :running, Activity.new(sport: "walk").sport_category
    assert_equal :other,   Activity.new(sport: "alpine_ski").sport_category
    assert_equal :other,   Activity.new(sport: "swim").sport_category
  end
end
