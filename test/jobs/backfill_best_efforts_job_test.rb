require "test_helper"
require_relative "../test_helpers/synthetic_track"

class BackfillBestEffortsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  # An activity stored without efforts, as one ingested before they existed.
  def stored_run(minutes_for_5k, on:)
    activity = @user.activities.create!(name: "Footing", sport: :run, start_time: on, end_time: on + 1.hour,
                                        location: "Paris", active_time: "PT3600S")
    SyntheticTrack.new(start: on).move(5_100, speed: 5_000.0 / (minutes_for_5k * 60), every: 300).points.each do |point|
      activity.activity_data_points.create!(recorded_at: point.recorded_at,
                                            location: "SRID=4326;POINT(#{point.lon} #{point.lat})")
    end
    activity
  end

  test "derives efforts from stored data points, ranked oldest first, and is idempotent" do
    newer = stored_run(25, on: Time.utc(2026, 2, 1))
    older = stored_run(20, on: Time.utc(2026, 1, 1))

    BackfillBestEffortsJob.perform_now
    snapshot = BestEffort.order(:id).pluck(:activity_id, :distance, :elapsed_seconds, :rank)

    assert_equal 1, older.best_efforts.find_by!(distance: "5k").rank
    assert_equal 2, newer.best_efforts.find_by!(distance: "5k").rank
    assert_in_delta 1_500, newer.best_efforts.find_by!(distance: "5k").elapsed_seconds, 1

    BackfillBestEffortsJob.perform_now
    assert_equal snapshot, BestEffort.order(:id).pluck(:activity_id, :distance, :elapsed_seconds, :rank)
  end

  test "the data migration enqueues the backfill" do
    require Rails.root.join("db/data/20261024121500_backfill_best_efforts")

    assert_enqueued_with(job: BackfillBestEffortsJob) do
      BackfillBestEfforts.new.up
    end
  end
end
