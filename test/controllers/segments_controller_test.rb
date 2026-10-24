require "test_helper"
require_relative "../test_helpers/segment_track_helper"

class SegmentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(map_hide_start_end_distance: 0)
    @activity = ingest_points(@user, points_at(ride(0, 2_000)), name: "Footing du parc")
    login(@user)
  end

  test "the activity page lists the segments ridden with time and PR badge" do
    segment = create_segment(from: 1_000, to: 1_500, name: "Montée du parc")
    perform_enqueued_jobs(only: BackfillSegmentEffortsJob)

    get activity_url(@activity)

    assert_response :success
    assert_select "#segment_efforts_activity_#{@activity.id}" do
      assert_select "li", text: /Montée du parc.*0:50.*PR/m
      assert_select "a[href=?]", segment_path(segment)
    end
  end

  test "the segment page shows the viewer's efforts and each rider's best public effort" do
    segment = create_segment(from: 1_000, to: 1_500, name: "Montée du parc")
    users(:two).update!(map_hide_start_end_distance: 0, name: "Camille")
    ingest_points(@user, points_at(ride(0, 2_000), every: 2, start: Time.utc(2026, 6, 2, 8)))
    ingest_points(users(:two), points_at(ride(0, 2_000), every: 3, start: Time.utc(2026, 6, 3, 8)))
    ingest_points(users(:two), points_at(ride(0, 2_000), every: 1, start: Time.utc(2026, 6, 4, 8)), visibility: :private)
    perform_enqueued_jobs(only: BackfillSegmentEffortsJob)

    get segment_url(segment)

    assert_response :success
    assert_select "h1", "Montée du parc"
    assert_select "#own_efforts_segment_#{segment.id} li", 2
    assert_select "#own_efforts_segment_#{segment.id} li.bg-warning\\/15", text: /0:50/
    assert_select "#leaderboard_segment_#{segment.id} tbody tr", 2
    assert_select "#leaderboard_segment_#{segment.id} tbody tr:nth-child(1)", text: /vous.*0:50/m
    assert_select "#leaderboard_segment_#{segment.id} tbody tr:nth-child(2)", text: /Camille.*2:30/m
  end

end
