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

  test "defaults to private visibility" do
    activity = activities(:one)
    assert_predicate activity, :visibility_private?
    assert_not activity.shareable_link?
  end

  test "shareable_link? is true for shareable and public visibility" do
    shareable = activities(:shareable)
    assert_predicate shareable, :visibility_shareable?
    assert shareable.shareable_link?

    shareable.update!(visibility: :public)
    assert shareable.shareable_link?
  end

  test "find_signed! round-trips with the :share purpose" do
    activity = activities(:shareable)
    token = activity.signed_id(purpose: :share)
    assert_equal activity, Activity.find_signed!(token, purpose: :share)
  end

  test "find_signed! raises when the purpose does not match" do
    activity = activities(:shareable)
    token = activity.signed_id(purpose: :share)
    assert_raises ActiveSupport::MessageVerifier::InvalidSignature do
      Activity.find_signed!(token, purpose: :something_else)
    end
  end
end
