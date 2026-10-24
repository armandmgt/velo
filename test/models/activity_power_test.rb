require "test_helper"
require_relative "../test_helpers/synthetic_track"

class ActivityPowerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  # Ingests and saves a 1 Hz ride (8 m/s) from `[watts, seconds]` blocks.
  def ride(*blocks, sport: :bike, on: Time.utc(2026, 6, 1, 8))
    track = SyntheticTrack.new(start: on, power: blocks.first.first)
    blocks.each { |watts, seconds| track.move(seconds * 8.0, speed: 8.0, power: watts) }
    activity = @user.activities.build(name: "Sortie", sport:)
    ActivityIngestion.call(activity, StringIO.new(track.to_gpx(type: "cycling")), filename: "ride.gpx",
                           reverse_geocode: false)
    activity.save!
    activity
  end

  # Stores heart-rate and power samples straight into an activity, 1 Hz.
  def store_samples(activity, heart_rate:, power:, seconds:)
    t = activity.start_time
    rows = Array.new(seconds + 1) do |i|
      { activity_id: activity.id, recorded_at: t + i, heart_rate:, power:, created_at: t, updated_at: t }
    end
    ActivityDataPoint.insert_all!(rows)
  end

  test "ingestion stores normalized power, a power curve and power best efforts" do
    activity = ride([ 200, 600 ], [ 300, 600 ], [ 200, 600 ])

    assert_operator activity.normalized_power, :>, 233.3
    assert_equal 300, activity.power_curve["300"]
    assert_equal 250, activity.power_curve["1200"]
    assert_equal 300, activity.power_curve["1"]
    assert_nil activity.power_curve["2400"], "the curve stops at the ride's length"

    efforts = activity.best_efforts.power.index_by(&:distance)
    assert_equal %w[power_10m power_1m power_20m power_30m power_30s power_5m power_5s].sort, efforts.keys.sort
    assert_in_delta 300, efforts["power_5m"].average_power, 0.01
    assert_in_delta 250, efforts["power_20m"].average_power, 0.01
    assert_equal 1, efforts["power_5m"].rank
    assert_operator efforts["power_5m"].start_index, :>=, 600, "offsets point into the path, at the 300 W block"
    assert_in_delta 300, efforts["power_5m"].end_index - efforts["power_5m"].start_index, 1
  end

  test "a ride without power, or a run with it, shows no power analysis" do
    no_power = @user.activities.build(name: "Sortie", sport: :bike)
    ActivityIngestion.call(no_power, StringIO.new(SyntheticTrack.new.move(2_000, speed: 8.0).to_gpx), filename: "r.gpx",
                           reverse_geocode: false)
    run = ride([ 250, 600 ], sport: :run)

    [ no_power, run ].each do |activity|
      assert_not activity.power_data?
      assert_nil activity.power_curve
      assert_empty activity.best_efforts.select(&:power?)
    end
  end

  test "with an FTP, a ride with power is scored by TSS" do
    @user.update_columns(ftp: 250, max_heart_rate: 200)

    activity = ride([ 200, 3_600 ])

    # 1 h at NP 200 W, IF 0.8: 3600 × 200 × 0.8 / (250 × 3600) × 100
    assert_equal 64.0, activity.effort_score
    assert activity.effort_score_source_power?
  end

  test "without an FTP, a ride keeps its heart-rate score; setting one switches it to power" do
    @user.update_columns(max_heart_rate: 200)
    activity = @user.activities.create!(name: "Sortie", sport: :bike, start_time: Time.utc(2026, 6, 1, 8),
                                        end_time: Time.utc(2026, 6, 1, 9), location: "Paris", active_time: "PT1800S",
                                        normalized_power: 300.0)
    store_samples(activity, heart_rate: 130, power: 300, seconds: 30 * 60)

    activity.recompute_effort_score!
    assert activity.reload.effort_score_source_heart_rate?
    assert_equal 60, activity.effort_score, "30 min in Z2"

    perform_enqueued_jobs { @user.update!(ftp: 300) }
    assert activity.reload.effort_score_source_power?
    assert_equal 50, activity.effort_score, "30 min at IF 1.0"

    perform_enqueued_jobs { @user.update!(ftp: 200) }
    assert_equal 112.5, activity.reload.effort_score, "the same ride at IF 1.5"

    perform_enqueued_jobs { @user.update!(ftp: nil) }
    assert activity.reload.effort_score_source_heart_rate?
  end

  test "Forme counts power scores" do
    @user.update_columns(ftp: 250)
    activity = ride([ 200, 3_600 ], on: Time.utc(2026, 6, 1, 8))

    forme = Forme.new(@user, today: Date.new(2026, 6, 1))

    assert_equal 64, forme.current.load
    assert activity.effort_score_source_power?
  end

  test "power zones follow Coggan's bands of FTP, and follow FTP changes" do
    activity = ride([ 100, 600 ], [ 260, 600 ])

    # The synthetic track stamps a block's power from its first second's end, so
    # the 100 W block owns one extra interval.
    zones = activity.power_zone_distribution(250)
    assert_equal 7, zones.size
    assert_equal [ 601, 0, 0, 599, 0, 0, 0 ], zones.map { it[:seconds] }
    assert_equal [ 50, 0, 0, 50, 0, 0, 0 ], zones.map { it[:percent] }
    assert_equal [ 0, 138 ], zones.first.values_at(:min_watts, :max_watts)
    assert_equal [ 375, nil ], zones.last.values_at(:min_watts, :max_watts)

    assert_equal [ 0, 601, 0, 0, 0, 0, 599 ], activity.power_zone_distribution(160).map { it[:seconds] }
    assert_nil activity.power_zone_distribution(nil)
  end

  test "a power dropout counts in no zone" do
    activity = @user.activities.create!(name: "Sortie", sport: :bike, start_time: Time.utc(2026, 6, 1, 8),
                                        end_time: Time.utc(2026, 6, 1, 9), location: "Paris", active_time: "PT1800S",
                                        normalized_power: 200.0)
    t = activity.start_time
    [ 0, 1, 2, 62, 63 ].each { |s| activity.activity_data_points.create!(recorded_at: t + s, power: 200) }

    assert_equal 3, activity.power_zone_distribution(250).sum { it[:seconds] }
  end
end
