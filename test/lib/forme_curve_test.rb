require "test_helper"

class FormeCurveTest < ActiveSupport::TestCase
  D = Date.new(2026, 3, 1)

  test "a 100-load day after a long rest moves fitness 1/42 and fatigue 1/7 of the way" do
    days = FormeCurve.new({ D => 100 }).days(from: D - 60, to: D + 1)
    load_day, next_day = days.last(2)

    # 100 / 42 and 100 / 7
    assert_in_delta 2.381, load_day.fitness, 0.001
    assert_in_delta 14.286, load_day.fatigue, 0.001
    assert_in_delta(-11.905, load_day.form, 0.001)

    # A rest day decays both: × 41/42 and × 6/7.
    assert_equal 0, next_day.load
    assert_in_delta 2.324, next_day.fitness, 0.001
    assert_in_delta 12.245, next_day.fatigue, 0.001
    assert_in_delta(-9.921, next_day.form, 0.001)
  end

  test "rest days before the first load stay at zero" do
    days = FormeCurve.new({ D => 100 }).days(from: D - 3, to: D - 1)

    assert_equal [ D - 3, D - 2, D - 1 ], days.map(&:date)
    assert(days.all? { |day| day.fitness.zero? && day.fatigue.zero? && day.form.zero? })
  end

  test "history before the window still shapes it" do
    days = FormeCurve.new({ D => 100 }).days(from: D + 1, to: D + 1)

    assert_equal 1, days.size
    assert_in_delta 2.324, days.first.fitness, 0.001
  end

  test "consecutive loads compound" do
    days = FormeCurve.new({ D => 100, D + 1 => 50 }).days(from: D, to: D + 1)

    # 100/42 = 2.381, then 2.381 + (50 - 2.381) / 42 = 3.515
    assert_in_delta 3.515, days.last.fitness, 0.001
    # 100/7 = 14.286, then 14.286 + (50 - 14.286) / 7 = 19.388
    assert_in_delta 19.388, days.last.fatigue, 0.001
  end

  test "no loads gives a flat zero curve" do
    days = FormeCurve.new({}).days(from: D, to: D + 6)

    assert_equal 7, days.size
    assert(days.all? { |day| day.fitness.zero? && day.fatigue.zero? })
  end
end
