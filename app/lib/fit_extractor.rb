class FitExtractor
  def initialize(activity, reverse_geocode: true)
    @rgeo_factory = RGeo::Geographic.spherical_factory(srid: 4326)
    @activity = activity
    @data_points = {}
    @set_location = false
    @reverse_geocode = reverse_geocode
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

    @data_points[msg["timestamp"]] ||= @activity.activity_data_points.build(recorded_at: Time.at(msg["timestamp"]))
    data_point = @data_points[msg["timestamp"]]

    if msg["position_lat"] && msg["position_long"]
      # Skip invalid values
      if msg["position_lat"].finite? && msg["position_long"].finite?
        data_point.location = @rgeo_factory.point(
          msg["position_long"], msg["position_lat"]
        )
      end

      # Set location once using first valid point
      if !@set_location
        @set_location = true
        if @reverse_geocode
          @activity.location ||= begin
            NominatimClient.new.reverse_geocode(msg["position_lat"], msg["position_long"]).then do |response|
              parts = response&.dig("reversegeocode", "addressparts")
              parts&.then { parts["village"] || parts["town"] || parts["city"] || parts["state"] || parts["country"] }
            end
          end
        else
          # Defer location enrichment; leave nil for now
        end
      end
    end

    %w[speed enhanced_speed].each do |name|
      if msg[name]
        data_point.speed = msg[name]
        if msg[name] > @activity.max_speed.to_f
          @activity.max_speed ||= msg[name]
        end
      end
    end

    if msg["heart_rate"]
      data_point.heart_rate = msg["heart_rate"]
    end

    if msg["cadence"]
      data_point.cadence = msg["cadence"]
    end

    if msg["power"]
      data_point.power = msg["power"]
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

  def finalize
    points = @data_points.values.map(&:location).compact
    return if points.empty?
    coords = points.map { |p| "#{p.longitude} #{p.latitude}" }.join(", ")
    @activity.path = "SRID=4326;LINESTRING(#{coords})"
  end
end
