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
      assert_select "a[href=?]", new_activity_segment_path(@activity)
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

  test "creates a segment from a stretch of the owner's activity and backfills it" do
    assert_enqueued_with(job: BackfillSegmentEffortsJob) do
      post activity_segments_url(@activity), params: { segment: { name: "Ligne droite", start_index: 50, end_index: 120 } }
    end

    segment = Segment.last
    assert_redirected_to segment_url(segment)
    assert_equal [ "Ligne droite", "running", @user ], [ segment.name, segment.sport_category, segment.user ]
    assert_in_delta 700, segment.distance, 1
  end

  test "rejects a segment under 200 m" do
    assert_no_difference -> { Segment.count } do
      post activity_segments_url(@activity), params: { segment: { name: "Court", start_index: 50, end_index: 60 } }
    end

    assert_response :unprocessable_content
    assert_select "[role=alert]", /200 m/
  end

  test "rejects a near-duplicate segment" do
    create_segment(from: 500, to: 1_200, name: "Existant")

    post activity_segments_url(@activity), params: { segment: { name: "Copie", start_index: 50, end_index: 120 } }

    assert_response :unprocessable_content
    assert_select "[role=alert]", /Existant/
  end

  test "segments are created only from the viewer's own activities" do
    other = ingest_points(users(:two), points_at(ride(0, 2_000)))

    get new_activity_segment_url(other)
    assert_response :not_found
  end

  test "the creation page offers the activity's track" do
    get new_activity_segment_url(@activity)

    assert_response :success
    assert_select "form[data-controller=segment-picker] input[type=range][name='segment[end_index]'][max='200']"
  end
end
