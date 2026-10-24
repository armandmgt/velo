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

  test "an update broadcasts a refresh to the owner's activities stream" do
    activity = activities(:one)
    recorded = capture_refresh_streams(activity) { activity.update!(name: "Nouveau nom") }
    assert_equal [ [ activity.user, :activities ] ], recorded
  end

  test "a destroy broadcasts a refresh to the owner's activities stream" do
    activity = activities(:one)
    recorded = capture_refresh_streams(activity) { activity.destroy! }
    assert_equal [ [ activity.user, :activities ] ], recorded
  end

  test "gear must belong to the activity's owner" do
    activity = activities(:one)
    activity.gear = gears(:other_users_bike)

    assert_not activity.valid?
    assert activity.errors.include?(:gear)
  end

  test "changing to a sport the gear doesn't fit drops the gear" do
    activity = activities(:one)
    activity.update!(gear: gears(:road_bike))

    activity.update!(sport: "gravel_ride")
    assert_equal gears(:road_bike), activity.reload.gear

    activity.update!(sport: "swim")
    assert_nil activity.reload.gear
  end

  private

  # Records the streamables passed to broadcast_refresh_later_to so we can assert
  # the target stream without exercising Turbo's async debouncer/job machinery.
  def capture_refresh_streams(activity)
    recorded = []
    activity.define_singleton_method(:broadcast_refresh_later_to) { |*args| recorded << args }
    yield
    recorded
  end
end
