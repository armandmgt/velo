require "test_helper"

class BestStretchTest < ActiveSupport::TestCase
  test "minimum finds the cheapest stretch spanning the axis" do
    stretch = BestStretch.new(axis: [ 0, 10, 20, 30, 40 ], measure: [ 0, 5, 7, 9, 20 ])

    best = stretch.minimum(20)

    assert_equal 1, best.start_index
    assert_equal 3, best.end_index
    assert_in_delta 4.0, best.value
  end

  test "maximum serves a power-by-duration window" do
    # axis: seconds elapsed; measure: cumulative joules from 100, 300, 300, 100 W.
    stretch = BestStretch.new(axis: [ 0, 1, 2, 3, 4 ], measure: [ 0, 100, 400, 700, 800 ])

    best = stretch.maximum(2)

    assert_equal 1, best.start_index
    assert_equal 3, best.end_index
    assert_in_delta 600.0 / 2, best.value / 2
  end

  test "interpolates the measure where the span ends between samples" do
    stretch = BestStretch.new(axis: [ 0, 40, 80 ], measure: [ 0, 10, 20 ])

    assert_in_delta 12.5, stretch.minimum(50).value
  end

  test "nothing when the series is shorter than the span" do
    stretch = BestStretch.new(axis: [ 0, 10 ], measure: [ 0, 1 ])

    assert_nil stretch.minimum(11)
    assert_nil BestStretch.new(axis: [], measure: []).maximum(1)
  end
end
