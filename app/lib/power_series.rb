# An activity's power samples, read as best averages over durations (power best
# efforts, power curve) and as normalized power. Knows nothing about
# ActiveRecord: it takes `[recorded_at, watts]` pairs in time order.
#
# Zeros are real, gaps are not. Coasting at 0 W is a sample like any other and
# drags every average containing it down. A missing sample isn't 0 W: wherever
# consecutive samples are further apart than `max_gap`, the series splits, and
# no window may span the split — so a dropout can neither fake a low average
# nor stitch two hard stretches into a spike.
#
# Each interval between samples carries its leading sample's power, as heart
# rate zones credit time, so at 1 Hz a 5 s window averages exactly 5 samples.
class PowerSeries
  NP_WINDOW = 30

  Best = Data.define(:seconds, :watts, :start_time, :end_time)

  Run = Data.define(:times, :stretch)

  def initialize(samples, max_gap: ActivityHeartRateZones::MAX_SAMPLE_GAP)
    @samples = samples.reject { |_, watts| watts.nil? }
    @max_gap = max_gap
  end

  def empty?
    runs.empty?
  end

  # Time actually covered by power data, gaps excluded.
  def seconds
    runs.sum { |run| run.times.last - run.times.first }
  end

  def best(duration)
    runs.filter_map { |run| best_in(run, duration) }.max_by(&:watts)
  end

  # { seconds => best average watts } for every ladder rung the series covers.
  def curve(ladder)
    ladder.each_with_object({}) do |duration, curve|
      best = best(duration) or break curve
      curve[duration] = best.watts.round
    end
  end

  # Coggan's weighted average power: the 30 s rolling average raised to the
  # 4th power, averaged, then the 4th root. Rolling windows never span a gap.
  def normalized_power
    sum = 0.0
    count = 0
    runs.each do |run|
      run.stretch.each_stretch(NP_WINDOW) do |window|
        sum += (window.value / NP_WINDOW)**4
        count += 1
      end
    end
    (sum / count)**0.25 if count.positive?
  end

  private

  attr_reader :samples, :max_gap

  def best_in(run, duration)
    best = run.stretch.maximum(duration) or return
    start_time = run.times[best.start_index]

    Best.new(seconds: duration, watts: best.value / duration, start_time:, end_time: start_time + duration)
  end

  def runs
    @runs ||= samples.chunk_while { |(t0, _), (t1, _)| (t1 - t0) <= max_gap }
                     .select { |run| run.size > 1 }
                     .map { |run| build_run(run) }
  end

  def build_run(run)
    origin  = run.first.first
    axis    = [ 0.0 ]
    joules  = [ 0.0 ]
    run.each_cons(2) do |(t0, watts), (t1, _)|
      axis   << (t1 - origin).to_f
      joules << joules.last + watts.to_f * (t1 - t0)
    end
    Run.new(times: run.map(&:first), stretch: BestStretch.new(axis:, measure: joules))
  end
end
