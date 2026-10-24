require "test_helper"
require_relative "../test_helpers/segment_track_helper"

class SegmentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(map_hide_start_end_distance: 0)
    @activity = ingest_points(@user, points_at(ride(0, 2_000)))
  end

  def from_activity(start_index, end_index, name: "Montée du stade")
    Segment.from_activity(@activity, start_index:, end_index:, name:)
  end

  test "is traced from the chosen stretch of the activity" do
    segment = from_activity(100, 150)

    assert segment.save
    assert_in_delta 500, segment.distance, 1
    assert_in_delta 25, segment.elevation_gain, 0.5
    assert_in_delta 5, segment.average_grade, 0.1
    assert_equal "running", segment.sport_category
    assert_equal @user, segment.user
    assert_equal segment.vertices.size, segment.altitudes.size
    assert_in_delta 1_000 / METERS_PER_DEGREE, segment.start_point.x, 1e-6
  end

  test "rejects a segment under 200 m" do
    segment = from_activity(100, 115)

    assert_not segment.save
    assert segment.errors.of_kind?(:distance, :greater_than_or_equal_to)
  end

  test "rejects a stretch whose end comes before its start" do
    assert_not from_activity(150, 100).save
  end

  test "rejects a near-duplicate in the same direction, not its reverse" do
    from_activity(100, 150).save!

    twin = from_activity(101, 151, name: "Copie")
    assert_not twin.save
    assert_match(/existe déjà/, twin.errors.full_messages.to_sentence)

    reverse = Segment.new(name: "Descente", sport_category: "running", user: @user)
    reverse.trace(points_at(ride(1_500, 1_000)).map { [ it.lat, it.lon, it.altitude ] })
    assert reverse.save
  end

  test "creating a segment backfills efforts through a job" do
    assert_enqueued_with(job: BackfillSegmentEffortsJob) { from_activity(100, 150).save! }
  end
end
