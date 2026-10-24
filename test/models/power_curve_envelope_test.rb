require "test_helper"

class PowerCurveEnvelopeTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 10, 24)

  setup do
    @user = users(:one)
    @user.activities.destroy_all
  end

  def ride(on, curve, sport: :bike)
    @user.activities.create!(name: "Sortie", sport:, start_time: on, end_time: on + 1.hour, location: "Paris",
                             active_time: "PT3600S", power_curve: curve)
  end

  def envelope(period = nil)
    PowerCurveEnvelope.new(@user, period:, today: TODAY)
  end

  test "all-time takes the best power per duration across rides, by increasing duration" do
    ride(Time.utc(2025, 5, 1), { "5" => 900, "60" => 400, "1200" => 280 })
    ride(Time.utc(2026, 10, 1), { "5" => 800, "60" => 450 })
    ride(Time.utc(2026, 10, 2), { "5" => 2_000 }, sport: :run)

    assert_equal [ [ 5, 900.0 ], [ 60, 450.0 ], [ 1200, 280.0 ] ], envelope.all_time
  end

  test "compares with the last 90 days by default, this year, or a past year" do
    ride(Time.utc(2025, 5, 1), { "5" => 900 })
    ride(Time.utc(2026, 3, 1), { "5" => 850 })
    ride(Time.utc(2026, 10, 1), { "5" => 800 })

    assert_equal "90d", envelope("bogus").period
    assert_equal [ [ 5, 800.0 ] ], envelope.compared
    assert_equal [ [ 5, 850.0 ] ], envelope("this_year").compared
    assert_equal [ [ 5, 900.0 ] ], envelope("2025").compared
    assert_equal %w[90d this_year 2025], envelope.periods.keys
  end

  test "empty without rides that have a curve" do
    ride(Time.utc(2026, 10, 1), nil)

    assert envelope.empty?
    assert_equal({ all_time: [], compared: [] }, envelope.chart_data)
  end
end
