# frozen_string_literal: true

# Re-derives per-point speeds and max_speed for every activity, de-spiking GPS
# data via ActivitySpeedRefilter (re-parse from source, recompute from stored
# positions, or trust device speed — see the service). Non-destructive and
# idempotent: speed is always re-derived from authoritative data.
class RefilterActivitySpeeds < ActiveRecord::Migration[8.1]
  def up
    Activity.find_each do |activity|
      before = activity.max_speed
      after = ActivitySpeedRefilter.call(activity)

      next if before == after
      say "Activity ##{activity.id} (#{activity.sport}): max_speed #{fmt(before)} -> #{fmt(after)} km/h"
    end
  end

  # Re-deriving from source/positions is the reversal; nothing to undo.
  def down; end

  private

  def fmt(speed_ms)
    speed_ms ? (speed_ms * 3.6).round(1) : "nil"
  end
end
