require "test_helper"

class IgpsportSyncServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # Credentials are encrypted and the test env has no keys; the sync only needs
    # the owner, a valid token and somewhere to record its status.
    @connection = Struct.new(:user) do
      def token_valid? = true
      def update(*) = true
    end.new(@user)
  end

  teardown do
    IgpsportClient.singleton_class.remove_method(:new) if IgpsportClient.singleton_class.instance_methods(false).include?(:new)
  end

  test "a synced ride gets its sport's default gear" do
    gears(:road_bike).update!(default_sports: %w[bike])
    stub_client(exercise_type: 0)

    result = IgpsportSyncService.new(@connection).call

    assert_equal 1, result[:imported], result[:errors].inspect
    assert_equal gears(:road_bike), @user.activities.find_by!(name: "Sortie iGPSport").gear
  end

  private

  # Follows the repo's stubbing idiom: swap the singleton `new`, remove it after.
  def stub_client(exercise_type:)
    fit = file_fixture("fit/bike.fit").binread
    ref = IgpsportClient::RideRef.new(ride_id: 1, start_date: Date.new(2001, 1, 1), distance: 0)
    detail = IgpsportClient::RideDetail.new(ride_id: 1, exercise_type: exercise_type, start_time: nil, end_time: nil,
                                            distance: 0, title: "Sortie iGPSport", fit_url: "https://example.com/1.fit")

    fake = Object.new
    fake.define_singleton_method(:activities) { |page: 1| { ride_refs: [ ref ], total_pages: 1 } }
    fake.define_singleton_method(:ride_detail) { |_ride_id| detail }
    fake.define_singleton_method(:download_fit) { |_url| fit }
    IgpsportClient.define_singleton_method(:new) { |_connection| fake }
  end
end
