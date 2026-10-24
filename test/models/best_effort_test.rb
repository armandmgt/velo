require "test_helper"
require_relative "../test_helpers/synthetic_track"

class BestEffortTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  # Ingests and saves a steady activity covering `meters` at `speed` m/s.
  def ingest(sport:, meters:, speed:, on: Time.utc(2026, 6, 1, 8))
    activity = @user.activities.build(name: "Sortie", sport:)
    ingest_into(activity, meters:, speed:, on:)
    activity.save!
    activity
  end

  def ingest_into(activity, meters:, speed:, on:)
    gpx = SyntheticTrack.new(start: on).move(meters, speed:, every: 250).to_gpx
    ActivityIngestion.call(activity, StringIO.new(gpx), filename: "track.gpx", reverse_geocode: false)
  end

  def five_k(activity)
    activity.best_efforts.find_by!(distance: "5k")
  end

  # A 5 km run taking `minutes`.
  def run_5k(minutes, on:)
    ingest(sport: :run, meters: 5_050, speed: 5_000.0 / (minutes * 60), on:)
  end

  test "a sport gets its own category's distances only" do
    run  = ingest(sport: :run,  meters: 11_000, speed: 3.0)
    ride = ingest(sport: :bike, meters: 11_000, speed: 8.0)
    hike = ingest(sport: :hike, meters: 11_000, speed: 1.5)

    assert_equal %w[1_mile 1k 2_miles 400m 5k 10k half_mile].sort, run.best_efforts.pluck(:distance).sort
    assert_equal %w[10k], ride.best_efforts.pluck(:distance)
    assert_empty hike.best_efforts
  end

  test "badges reflect the standing when each activity was ingested" do
    run_5k(25, on: Time.utc(2026, 1, 1))
    run_5k(26, on: Time.utc(2026, 1, 2))

    third  = run_5k(27,   on: Time.utc(2026, 2, 1))
    second = run_5k(25.5, on: Time.utc(2026, 3, 1))
    pr     = run_5k(24,   on: Time.utc(2026, 4, 1))

    assert_equal 3, five_k(third).rank
    assert_equal 2, five_k(second).rank
    assert_equal 1, five_k(pr).rank
    assert_equal 3, five_k(third.reload).rank, "a later, faster effort doesn't strip an old badge"
  end

  test "a slower effort off the podium earns no badge, and other categories don't compete" do
    run_5k(20, on: Time.utc(2026, 1, 1))
    run_5k(21, on: Time.utc(2026, 1, 2))
    run_5k(22, on: Time.utc(2026, 1, 3))
    ride = ingest(sport: :bike, meters: 11_000, speed: 2.0, on: Time.utc(2026, 1, 4))

    assert_nil five_k(run_5k(30, on: Time.utc(2026, 2, 1))).rank
    assert_equal 1, ride.best_efforts.find_by!(distance: "10k").rank
  end

  test "a removed effort doesn't rank later ones" do
    glitch = run_5k(10, on: Time.utc(2026, 1, 1))
    five_k(glitch).remove!

    assert_equal 1, five_k(run_5k(25, on: Time.utc(2026, 2, 1))).rank
  end

  # Saving a re-ingested activity isn't possible yet (its data points would be
  # duplicated), so this checks the efforts at the ingestion seam.
  test "re-ingesting an activity replaces its efforts" do
    activity = run_5k(25, on: Time.utc(2026, 1, 1)).reload
    original = activity.best_efforts.detect { |effort| effort.distance == "5k" }

    ingest_into(activity, meters: 5_050, speed: 5_000.0 / (20 * 60), on: Time.utc(2026, 1, 1))

    assert original.marked_for_destruction?
    assert activity.best_efforts.reject(&:marked_for_destruction?).all?(&:new_record?)
    replacement = activity.best_efforts.find { |effort| effort.new_record? && effort.distance == "5k" }
    assert_in_delta 20 * 60, replacement.elapsed_seconds, 1
    assert_equal 1, replacement.rank, "an activity doesn't compete with its own previous efforts"
  end
end
