require "test_helper"

class PowerSeriesTest < ActiveSupport::TestCase
  START = Time.utc(2026, 6, 1, 8)

  # 1 Hz samples from `[watts, seconds]` blocks, plus a closing sample so the
  # last block is fully covered.
  def samples(*blocks, start: START)
    t = start
    pairs = blocks.flat_map do |watts, seconds|
      Array.new(seconds) { |i| [ t + i, watts ] }.tap { t += seconds }
    end
    pairs << [ t, blocks.last.first ]
  end

  def series(*blocks)
    PowerSeries.new(samples(*blocks))
  end

  test "30 min at 200 W around a 10-min 300 W block" do
    ride = series([ 200, 600 ], [ 300, 600 ], [ 200, 600 ])

    assert_in_delta 300, ride.best(300).watts, 0.01
    assert_in_delta 250, ride.best(1_200).watts, 0.01, "the whole block plus 10 min at 200 W"
    assert_operator ride.normalized_power, :>, 225
    assert_operator ride.normalized_power, :>, (200 * 20 + 300 * 10) / 30.0, "NP weighs the block above the plain average"
  end

  test "30 min at 200 W around a 5-min 300 W block gives a best 20 min of 225 W" do
    ride = series([ 200, 600 ], [ 300, 300 ], [ 200, 900 ])

    assert_in_delta 300, ride.best(300).watts, 0.01
    assert_in_delta 225, ride.best(1_200).watts, 0.01
    assert_operator ride.normalized_power, :>, 225
  end

  test "a 60-second dropout splits the series: no window spans it" do
    before = samples([ 250, 600 ])
    after  = samples([ 250, 600 ], start: before.last.first + 60)
    ride = PowerSeries.new(before + after)

    assert_nil ride.best(900), "neither side holds 15 minutes"
    assert_in_delta 250, ride.best(600).watts, 0.01, "the gap is not averaged in as 0 W"
    assert_in_delta 1_200, ride.seconds, 0.01
    assert_in_delta 250, ride.normalized_power, 0.01
  end

  test "a 60-second coast at 0 W lowers the averages that include it" do
    ride = series([ 250, 600 ], [ 0, 60 ], [ 250, 600 ])

    assert_in_delta 250 * 600.0 / 900 + 250 * 240.0 / 900, ride.best(900).watts, 0.01
    assert_operator ride.normalized_power, :<, 250
    assert_in_delta 1_260, ride.seconds, 0.01
  end

  test "best carries the window's wall-clock bounds" do
    best = series([ 100, 60 ], [ 400, 5 ], [ 100, 60 ]).best(5)

    assert_in_delta 400, best.watts, 0.01
    assert_equal START + 60, best.start_time
    assert_equal START + 65, best.end_time
  end

  test "the curve stops at the longest covered duration and ignores missing samples" do
    pairs = samples([ 300, 10 ], [ 150, 50 ])
    pairs.insert(5, [ START + 5.5, nil ])

    assert_equal({ 1 => 300, 10 => 300, 60 => 175 }, PowerSeries.new(pairs).curve([ 1, 10, 60, 120 ]))
  end

  test "no power, no figures" do
    ride = PowerSeries.new([ [ START, nil ], [ START + 1, nil ] ])

    assert ride.empty?
    assert_nil ride.best(5)
    assert_nil ride.normalized_power
    assert_empty ride.curve([ 1, 5 ])
  end
end
