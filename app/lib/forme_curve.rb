# Daily fitness, fatigue and form from daily effort scores. See CONTEXT.md
# ("Forme").
#
# Fitness and fatigue are exponentially weighted averages of daily load with the
# usual 42- and 7-day constants: each day moves the average 1/42 (or 1/7) of the
# way towards that day's load. A day without activity has zero load and still
# decays both. Form is fitness minus fatigue on the same day.
class FormeCurve
  FITNESS_DAYS = 42
  FATIGUE_DAYS = 7

  Day = Data.define(:date, :load, :fitness, :fatigue, :form)

  # `daily_loads`: { Date => summed effort score }.
  def initialize(daily_loads)
    @daily_loads = daily_loads
  end

  # Days `from..to`. The averages start from zero on the earliest loaded day, so
  # history before `from` still shapes the window.
  def days(from:, to:)
    start = [ @daily_loads.keys.min, from ].compact.min
    fitness = fatigue = 0.0

    (start..to).filter_map do |date|
      load = @daily_loads.fetch(date, 0).to_f
      fitness += (load - fitness) / FITNESS_DAYS
      fatigue += (load - fatigue) / FATIGUE_DAYS
      Day.new(date:, load:, fitness:, fatigue:, form: fitness - fatigue) if date >= from
    end
  end
end
