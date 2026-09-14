# frozen_string_literal: true

# Re-derives per-point speeds and max_speed for every activity, de-spiking GPS
# data. Non-destructive and idempotent: speed is always re-derived from
# authoritative data (the stored GPS positions, or the device speed).
#
# The distance and Hampel-filter code below is deliberately COPIED rather than
# required from app/lib. A historical data migration has to keep running years
# after the app code it was written against has moved on, and this file is the
# one place where duplication is the point rather than a smell. Calling
# ActivityIngestion or ::SpeedFilter here would re-couple it to a live interface.
# See docs/adr/0004-ingestion-stops-before-persistence.md for the surrounding
# refactor; the original lived in app/services/activity_speed_refilter.rb before
# commit "Delete ActivitySpeedRefilter".
#
# The original also had a third branch that re-parsed the retained Source file.
# It was dropped: for a GPX source it produced the same positions already stored,
# and for a FIT source the same device speeds already stored, so branches below
# reach the same result without depending on the extractors (and, for FIT, on the
# RubyFit C extension).
class RefilterActivitySpeeds < ActiveRecord::Migration[8.1]
  def up
    Activity.find_each do |activity|
      before = activity.max_speed
      after = Refilter.new(activity).call

      next if before == after
      say "Activity ##{activity.id} (#{activity.sport}): max_speed #{fmt(before)} -> #{fmt(after)} km/h"
    end
  end

  # Re-deriving from positions is the reversal; nothing to undo.
  def down; end

  private

  def fmt(speed_ms)
    speed_ms ? (speed_ms * 3.6).round(1) : "nil"
  end

  # Great-circle distance in meters. Frozen copy of Haversine.
  module Distance
    EARTH_RADIUS_M = 6_371_000.0

    module_function

    def between(lat1, lon1, lat2, lon2)
      rlat1 = lat1 * Math::PI / 180
      rlat2 = lat2 * Math::PI / 180
      dlat = (lat2 - lat1) * Math::PI / 180
      dlon = (lon2 - lon1) * Math::PI / 180

      a = Math.sin(dlat / 2)**2 +
          Math.cos(rlat1) * Math.cos(rlat2) * Math.sin(dlon / 2)**2
      EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end
  end

  # Hampel filter (rolling median + MAD). Frozen copy of SpeedFilter.
  class Hampel
    WINDOW = 7
    THRESHOLD = 3.0
    MAD_SCALE = 1.4826
    SIGMA_FLOOR = 0.5
    MIN_NEIGHBOURS = 4

    def filter!(points)
      speeds = points.map(&:speed)

      speeds.each_index do |i|
        next if speeds[i].nil?

        window = window_values(speeds, i)
        next if window.size <= MIN_NEIGHBOURS

        med = median(window)
        sigma = [ median(window.map { |s| (s - med).abs }) * MAD_SCALE, SIGMA_FLOOR ].max

        points[i].speed = nil if (speeds[i] - med).abs > THRESHOLD * sigma
      end

      points.filter_map(&:speed).max
    end

    private

    def window_values(speeds, index)
      lo = [ index - WINDOW, 0 ].max
      hi = [ index + WINDOW, speeds.size - 1 ].min
      speeds[lo..hi].compact
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end
  end

  class Refilter
    def initialize(activity)
      @activity = activity
    end

    def call
      if device_speeds? || !gps?
        refresh_max_from_stored
      else
        refilter_from_positions
      end
      activity.max_speed
    end

    private

    attr_reader :activity

    # A retained FIT source means the stored per-point speeds came from the
    # device (Doppler / wheel sensor) and are trusted as-is — recomputing them
    # from GPS positions would be strictly worse data. Read through
    # ActiveStorage directly, and accept either attachment name, so this stays
    # correct across the fit_file -> source_file rename.
    def device_speeds?
      filename = ActiveStorage::Attachment
                   .where(record_type: "Activity", record_id: activity.id,
                          name: %w[source_file fit_file])
                   .joins(:blob)
                   .pick("active_storage_blobs.filename")

      filename.present? && !filename.downcase.end_with?(".gpx")
    end

    def refilter_from_positions
      points = activity.activity_data_points.order(:recorded_at).to_a
      recompute_position_speeds(points)
      Hampel.new.filter!(points)
      points.each { |point| point.save!(validate: false) if point.changed? }
      activity.update_column(:max_speed, points.filter_map(&:speed).max)
    end

    def refresh_max_from_stored
      activity.update_column(:max_speed, activity.activity_data_points.maximum(:speed))
    end

    # Per-point speed as the great-circle distance from the previous located
    # point divided by the elapsed time.
    def recompute_position_speeds(points)
      prev = nil
      points.each do |point|
        loc = point.location
        if prev && loc
          dt = (point.recorded_at - prev.recorded_at).to_f
          distance = Distance.between(prev.location.y, prev.location.x, loc.y, loc.x)
          point.speed = dt.positive? ? distance / dt : nil
        else
          point.speed = nil
        end
        prev = point if loc
      end
    end

    def gps?
      activity.activity_data_points.where.not(location: nil).exists?
    end
  end
end
