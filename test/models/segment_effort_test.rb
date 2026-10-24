require "test_helper"
require_relative "../test_helpers/segment_track_helper"

class SegmentEffortTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(map_hide_start_end_distance: 0)
    @segment = create_segment(from: 1_000, to: 1_500)
  end

  test "ingestion times each pass from start to end, and a reverse ride is no effort" do
    forward = ingest_points(@user, points_at(ride(0, 2_000)))
    backward = ingest_points(@user, points_at(ride(2_000, 0)))

    effort = forward.segment_efforts.sole
    assert_equal @segment, effort.segment
    assert_equal [ 100, 150, 50.0 ], [ effort.start_index, effort.end_index, effort.elapsed_seconds ]
    assert_empty backward.segment_efforts
  end

  test "a segment of another sport category is not matched" do
    assert_empty ingest_points(@user, points_at(ride(0, 2_000)), sport: :bike).segment_efforts
  end

  test "three repeats give three efforts and one leaderboard row with the best" do
    laps = [ 2, 1, 3 ].flat_map { |every| ride(900, 1_600).map { [ it, every ] } + ride(1_590, 910).map { [ it, 1 ] } }
    start = Time.utc(2026, 6, 1, 8)
    points = laps.each_with_object([]) do |(meters, every), acc|
      at = acc.empty? ? start : acc.last.recorded_at + every
      acc << points_at([ meters ], start: at).first
    end
    activity = ingest_points(@user, points)

    assert_equal [ 100.0, 50.0, 150.0 ], activity.segment_efforts.sort_by(&:start_index).map(&:elapsed_seconds)
    assert_equal [ 1, 1, 3 ], activity.segment_efforts.sort_by(&:start_index).map(&:rank)
    assert_equal [ [ @user.id, 50.0 ] ], @segment.leaderboard.map { [ it.activity.user_id, it.elapsed_seconds ] }
  end

  test "a private activity's effort counts for the rider's PRs but not the leaderboard" do
    activity = ingest_points(@user, points_at(ride(0, 2_000)), visibility: :private)

    effort = activity.segment_efforts.sole
    assert effort.private?
    assert_equal 1, effort.rank
    assert_includes @segment.efforts_by(@user), effort
    assert_empty @segment.leaderboard
  end

  test "an effort starting inside the hidden portion is private" do
    @user.update!(map_hide_start_end_distance: 1_200)

    assert ingest_points(@user, points_at(ride(0, 3_000))).segment_efforts.sole.private?
  end

  test "an effort ending inside an address zone is private" do
    @user.map_privacy_zones.create!(latitude: 0, longitude: 1_500 / METERS_PER_DEGREE, radius: 200)

    assert ingest_points(@user, points_at(ride(0, 3_000))).segment_efforts.sole.private?
  end

  test "making the activity public or hiding its map updates the private flag" do
    activity = ingest_points(@user, points_at(ride(0, 2_000)), visibility: :private)

    activity.update!(visibility: :public)
    assert_not activity.segment_efforts.sole.reload.private?

    activity.update!(map_hidden: true)
    assert activity.segment_efforts.sole.reload.private?
  end

  test "PR / 2nd / 3rd rank against the rider's earlier efforts only" do
    ranks = [ [ 3, 1 ], [ 2, 2 ], [ 1, 3 ], [ 4, 4 ] ].map do |every, day|
      points = points_at(ride(0, 2_000), every:, start: Time.utc(2026, 6, day, 8))
      ingest_points(@user, points).segment_efforts.sole.rank
    end
    other = ingest_points(users(:two), points_at(ride(0, 2_000), every: 5, start: Time.utc(2026, 6, 5, 8)))

    assert_equal [ 1, 1, 1, nil ], ranks
    assert_equal 1, other.segment_efforts.sole.rank
    assert_equal [ users(:two).id, @user.id ].sort, @segment.leaderboard.map { it.activity.user_id }.sort
    assert_equal @user.id, @segment.leaderboard.first.activity.user_id
  end

  test "a later, slower effort earns 2nd or 3rd" do
    ranks = [ [ 1, 1 ], [ 3, 2 ], [ 2, 3 ] ].map do |every, day|
      ingest_points(@user, points_at(ride(0, 2_000), every:, start: Time.utc(2026, 6, day, 8))).segment_efforts.sole.rank
    end

    assert_equal [ 1, 2, 2 ], ranks
  end

  # Checked at the ingestion seam, as for best efforts: saving a re-ingested
  # activity would duplicate its data points.
  test "re-ingesting an activity recomputes its efforts" do
    activity = ingest_points(@user, points_at(ride(0, 2_000))).reload
    original = activity.segment_efforts.to_a.sole
    ActivityIngestion.call(activity, StringIO.new(gpx_for(points_at(ride(0, 2_000), every: 2))),
                           filename: "track.gpx", reverse_geocode: false)

    assert original.marked_for_destruction?
    replacement = activity.segment_efforts.reject(&:marked_for_destruction?).sole
    assert_equal [ 100.0, 1 ], [ replacement.elapsed_seconds, replacement.rank ]
  end

  test "the spatial pre-filter keeps the precise match to nearby segments among 1,000" do
    far = Array.new(1_000) do |i|
      lat = 1 + (i / 40) * 0.01
      lon = (i % 40) * 0.01
      { name: "Loin #{i}", sport_category: "running", distance: 500,
        path: "SRID=4326;LINESTRING(#{lon} #{lat}, #{lon + 0.0045} #{lat})",
        start_point: "SRID=4326;POINT(#{lon} #{lat})", end_point: "SRID=4326;POINT(#{lon + 0.0045} #{lat})" }
    end
    Segment.insert_all!(far)

    matched = 0
    original = SegmentMatcher.method(:new)
    SegmentMatcher.define_singleton_method(:new) { |*args| matched += 1; original.call(*args) }
    activity = ingest_points(@user, points_at(ride(0, 2_000)))

    assert_equal 1, matched
    assert_equal [ @segment ], activity.segment_efforts.map(&:segment)
  ensure
    SegmentMatcher.singleton_class.remove_method(:new) if SegmentMatcher.singleton_class.method_defined?(:new, false)
  end
end
