require "test_helper"
require_relative "../test_helpers/segment_track_helper"

class BackfillSegmentEffortsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    [ users(:one), users(:two) ].each { it.update!(map_hide_start_end_distance: 0) }
  end

  test "matches a new segment against every user's existing activities, ranked in order" do
    slow  = ingest_points(users(:one), points_at(ride(0, 2_000), every: 2, start: Time.utc(2026, 6, 1, 8)))
    fast  = ingest_points(users(:one), points_at(ride(0, 2_000), every: 1, start: Time.utc(2026, 6, 2, 8)))
    other = ingest_points(users(:two), points_at(ride(0, 2_000), every: 3, start: Time.utc(2026, 6, 3, 8)),
                          visibility: :private)
    elsewhere = ingest_points(users(:two), points_at(ride(5_000, 7_000)))

    segment = create_segment(from: 1_000, to: 1_500)
    perform_enqueued_jobs(only: BackfillSegmentEffortsJob)

    assert_equal [ 100.0, 1 ], slow.segment_efforts.reload.sole.then { [ it.elapsed_seconds, it.rank ] }
    assert_equal [ 50.0, 1 ], fast.segment_efforts.reload.sole.then { [ it.elapsed_seconds, it.rank ] }
    assert other.segment_efforts.reload.sole.private?
    assert_empty elsewhere.segment_efforts.reload
    assert_equal [ fast.id ], segment.leaderboard.map(&:activity_id)
  end

  test "running again adds nothing" do
    activity = ingest_points(users(:one), points_at(ride(0, 2_000)))
    segment = create_segment(from: 1_000, to: 1_500)

    2.times { BackfillSegmentEffortsJob.perform_now(segment) }

    assert_equal 1, activity.segment_efforts.count
  end
end
