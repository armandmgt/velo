# Reads a FIT file into a Track.
#
# The RubyFit parser drives an observer object, calling eleven `on_*` / `print_*`
# methods on it unconditionally (see ext/ruby_fit/ruby_fit.c — they are
# `rb_funcall`s, not `respond_to?` checks). That protocol is an internal seam:
# Sink satisfies it, and callers never see it.
class FitExtractor
  # `file_id.type` for an activity file. Anything else is a device, workout or
  # course file that happens to be FIT.
  ACTIVITY_FILE_TYPE = 4

  def initialize(fit_string)
    @fit_string = fit_string
  end

  def extract
    sink = Sink.new
    RubyFit::Parser.new(sink).parse(@fit_string)
    sink.to_track
  end

  # Satisfies the RubyFit observer protocol. Every method here is required by the
  # C extension; the ones that only log are required by it too.
  class Sink
    def initialize
      @points   = {}
      @summary  = Track::Summary.empty
      @problems = []
    end

    def to_track
      points = @points.values
      Track.new(
        points: points,
        # FIT speed comes from the device (Doppler / wheel sensor) and is already
        # clean, so it is trusted as-is — just take the maximum.
        summary: @summary.with(max_speed: points.filter_map(&:speed).max),
        problems: @problems
      )
    end

    def print_msg(msg)
      Rails.logger.info msg
    end

    def print_error_msg(msg)
      Rails.logger.error msg
    end

    def on_file_id(msg)
      Rails.logger.info "file id: #{msg.inspect}"

      @problems << :invalid_file_type if msg["type"] != ACTIVITY_FILE_TYPE
    end

    def on_session(msg)
      Rails.logger.info "session: #{msg.inspect}"

      @summary = @summary.with(
        start_time:     Time.at(msg["start_time"]).utc,
        end_time:       Time.at(msg["start_time"] + msg["total_elapsed_time"]).utc,
        moving_seconds: msg["total_timer_time"].to_i,
        elevation_gain: msg["total_ascent"],
        distance:       msg["total_distance"]
      )
    end

    def on_record(msg)
      Rails.logger.info "record: #{msg.inspect}"

      point = (@points[msg["timestamp"]] ||= Track::Point.new(recorded_at: Time.at(msg["timestamp"])))

      if msg["position_lat"] && msg["position_long"] &&
         msg["position_lat"].finite? && msg["position_long"].finite?
        point.lat = msg["position_lat"]
        point.lon = msg["position_long"]
      end

      # The enhanced_* variants carry the wider range; prefer them when present.
      %w[speed enhanced_speed].each { |name| point.speed = msg[name] if msg[name] }
      %w[altitude enhanced_altitude].each { |name| point.altitude = msg[name] if msg[name] }

      point.heart_rate = msg["heart_rate"] if msg["heart_rate"]
      point.cadence    = msg["cadence"]    if msg["cadence"]
      point.power      = msg["power"]      if msg["power"]
    end

    def on_activity(msg)
      Rails.logger.info "activity: #{msg.inspect}"
    end

    def on_lap(msg)
      Rails.logger.info "lap: #{msg.inspect}"
    end

    def on_event(msg)
      Rails.logger.info "event: #{msg.inspect}"
    end

    def on_device_info(msg)
      Rails.logger.info "device info: #{msg.inspect}"
    end

    def on_user_profile(msg)
      Rails.logger.info "user profile: #{msg.inspect}"
    end

    def on_weight_scale_info(msg)
      Rails.logger.info "weight scale info: #{msg.inspect}"
    end
  end
end
