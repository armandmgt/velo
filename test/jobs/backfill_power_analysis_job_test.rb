require "test_helper"

class BackfillPowerAnalysisJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  # A ride stored without power analysis, as one ingested before it existed:
  # 10 minutes at `watts`, 1 Hz, located.
  def stored_ride(watts, on:, sport: :bike)
    activity = @user.activities.create!(name: "Sortie", sport:, start_time: on, end_time: on + 1.hour,
                                        location: "Paris", active_time: "PT600S")
    rows = Array.new(601) do |i|
      { activity_id: activity.id, recorded_at: on + i, power: watts, location: "SRID=4326;POINT(#{i * 0.0001} 0)",
        created_at: on, updated_at: on }
    end
    ActivityDataPoint.insert_all!(rows)
    activity
  end

  test "derives NP, the curve and ranked power efforts oldest first, rescores with FTP, and is idempotent" do
    @user.update_columns(ftp: 250)
    newer = stored_ride(200, on: Time.utc(2026, 2, 1))
    older = stored_ride(300, on: Time.utc(2026, 1, 1))
    run   = stored_ride(300, on: Time.utc(2026, 1, 3), sport: :run)

    BackfillPowerAnalysisJob.perform_now
    snapshot = BestEffort.order(:id).pluck(:activity_id, :distance, :average_power, :rank)

    assert_in_delta 200, newer.reload.normalized_power, 0.01
    assert_equal 200, newer.power_curve["600"]
    assert_equal 1, older.best_efforts.find_by!(distance: "power_5m").rank
    assert_equal 2, newer.best_efforts.find_by!(distance: "power_5m").rank
    assert_equal [ 0, 300 ], older.best_efforts.find_by!(distance: "power_5m").values_at(:start_index, :end_index)
    assert newer.effort_score_source_power?
    # 600 s at IF 0.8: 600 × 200 × 0.8 / (250 × 3600) × 100
    assert_equal 10.7, newer.effort_score
    assert_nil run.reload.normalized_power

    BackfillPowerAnalysisJob.perform_now
    assert_equal snapshot, BestEffort.order(:id).pluck(:activity_id, :distance, :average_power, :rank)
  end

  test "the data migration enqueues the backfill" do
    require Rails.root.join("db/data/20261024140500_backfill_power_analysis")

    assert_enqueued_with(job: BackfillPowerAnalysisJob) do
      BackfillPowerAnalysis.new.up
    end
  end
end
