require "test_helper"

class ActivityHeartRateZonesTest < ActiveSupport::TestCase
  setup do
    @activity = activities(:one)
    @activity.activity_data_points.destroy_all
  end

  test "returns nil when no max HR is provided" do
    add_points([ 110, 130 ])
    assert_nil @activity.heart_rate_zone_distribution(nil)
  end

  test "returns nil when there is no heart-rate data" do
    t = Time.zone.parse("2026-01-01 10:00:00")
    @activity.activity_data_points.create!(recorded_at: t, speed: 5.0)
    assert_nil @activity.heart_rate_zone_distribution(200)
  end

  test "attributes bounded time to the matching zone of each leading sample" do
    # max_hr 200 → boundaries 120 / 140 / 160 / 180.
    # each_cons pairs attribute dt to the first sample's HR.
    add_points([ 110, 130, 150, 190, 190 ]) # Z1, Z2, Z3, Z5, (trailing)

    zones = @activity.heart_rate_zone_distribution(200)

    assert_equal 1, zones[0][:seconds] # Z1 (110)
    assert_equal 1, zones[1][:seconds] # Z2 (130)
    assert_equal 1, zones[2][:seconds] # Z3 (150)
    assert_equal 0, zones[3][:seconds] # Z4 (none)
    assert_equal 1, zones[4][:seconds] # Z5 (190)

    assert_equal 25, zones[0][:percent]
    assert_equal 0, zones[3][:percent]
    assert_equal 100, zones.sum { _1[:percent] }
  end

  test "exposes bpm ranges derived from max HR" do
    add_points([ 110, 130 ])
    zones = @activity.heart_rate_zone_distribution(200)

    assert_equal 0, zones[0][:min_bpm]
    assert_equal 120, zones[0][:max_bpm]
    assert_equal 120, zones[1][:min_bpm]
    assert_equal 140, zones[1][:max_bpm]
    assert_equal 180, zones[4][:min_bpm]
    assert_nil zones[4][:max_bpm]
  end

  test "caps the gap between sparse samples" do
    t = Time.zone.parse("2026-01-01 10:00:00")
    @activity.activity_data_points.create!(recorded_at: t, heart_rate: 110)
    @activity.activity_data_points.create!(recorded_at: t + 1.hour, heart_rate: 130)

    zones = @activity.heart_rate_zone_distribution(200)

    # The hour-long gap is capped at MAX_SAMPLE_GAP (10s), all in Z1.
    assert_equal ActivityHeartRateZones::MAX_SAMPLE_GAP, zones[0][:seconds]
  end

  private

  def add_points(heart_rates)
    t = Time.zone.parse("2026-01-01 10:00:00")
    heart_rates.each_with_index do |hr, i|
      @activity.activity_data_points.create!(recorded_at: t + i.seconds, heart_rate: hr)
    end
  end
end
