class FitExtractor
  def initialize(activity)
    @activity = activity
    @found_position_record = false
  end

  def print_msg(msg)
    Rails.logger.info msg
  end

  def print_error_msg(msg)
    Rails.logger.error msg
  end

  def on_file_id(msg)
    Rails.logger.info "file id: #{msg.inspect}"

    @activity.errors.add(:fit_file, :invalid_file_type) if msg["type"] != 4
  end

  def on_activity(msg)
    Rails.logger.info "activity: #{msg.inspect}"
  end

  def on_lap(msg)
    Rails.logger.info "lap: #{msg.inspect}"
  end

  def on_session(msg)
    Rails.logger.info "session: #{msg.inspect}"

    @activity.start_time = Time.at(msg["start_time"]).utc
    @activity.end_time = Time.at(msg["start_time"] + msg["total_elapsed_time"]).utc

    @activity.active_time = ActiveSupport::Duration.build(msg["total_timer_time"].to_i).iso8601
    @activity.total_elevation_gain = msg["total_ascent"]
    @activity.distance = msg["total_distance"]
  end

  def on_record(msg)
    Rails.logger.info "record: #{msg.inspect}"

    if msg["position_lat"] && msg["position_long"] && !@found_position_record
      @found_position_record = true
      @activity.positions ||= Activity::Positions.new(msg["position_lat"], msg["position_long"])
      @activity.location ||= begin
        NominatimClient.new.reverse_geocode(msg["position_lat"], msg["position_long"]).then do |response|
          parts = response.dig("reversegeocode", "addressparts")
          parts["village"] || parts["town"] || parts["city"] || parts["state"] || parts["country"]
        end
      end
    end
    if msg["speed"] && msg["speed"] > @activity.max_speed.to_f
      @activity.max_speed ||= msg["speed"]
    end
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
