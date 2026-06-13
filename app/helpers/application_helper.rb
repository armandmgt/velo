module ApplicationHelper
  # DaisyUI alert modifier for a flash type. `notice` is treated as success,
  # `alert` as error; other keys fall back to their own modifier or info.
  def flash_alert_class(type)
    case type.to_s
    when "notice", "success" then "alert-success"
    when "alert", "error"    then "alert-error"
    when "warning"           then "alert-warning"
    else                          "alert-info"
    end
  end

  def flash_alert_icon(type)
    case type.to_s
    when "notice", "success" then "circle-check"
    when "alert", "error"    then "circle-x"
    when "warning"           then "triangle-alert"
    else                          "info"
    end
  end

  def sport_grouped_options(selected = nil)
    grouped_sport_options(Activity.sports.each_key, selected)
  end

  def routable_sport_grouped_options(selected = nil)
    grouped_sport_options(PlannedRoute.sports.each_key, selected)
  end

  def grouped_sport_options(sport_keys, selected)
    group_labels = {
      cycling: I18n.t("activity.sport_group.cycling"),
      running: I18n.t("activity.sport_group.running"),
      other:   I18n.t("activity.sport_group.other")
    }
    grouped = group_labels.transform_values { [] }
    sport_keys.each do |key|
      category = Activity::SPORT_CATEGORY[key.to_sym]
      grouped[category] << [ I18n.t("activity.sport.#{key}"), key ]
    end
    grouped_options_for_select(
      grouped.reject { |_cat, options| options.empty? }
             .map { |cat, options| [ group_labels[cat], options ] },
      selected
    )
  end

  def duration_display(duration)
    duration.parts.map do |_key, value|
      value.to_s.rjust(2, "0")
    end.join(":")
  end

  def format_duration_hms(total_seconds)
    total = total_seconds.to_i
    h = total / 3600
    m = (total % 3600) / 60
    s = total % 60
    "#{h}:#{m.to_s.rjust(2, '0')}:#{s.to_s.rjust(2, '0')}"
  end

  # Pace formatted as "m:ss /km" from seconds-per-kilometer.
  def pace_display(seconds_per_km)
    minutes = (seconds_per_km / 60).floor
    seconds = (seconds_per_km % 60).round
    if seconds == 60
      minutes += 1
      seconds = 0
    end
    "#{minutes}:#{seconds.to_s.rjust(2, '0')} /km"
  end

  # Ordered, nil-filtered summary metrics for an activity, sport-aware
  # (pace for running, speed for everything else). Each entry: { label:, value:, icon: }.
  def activity_summary_metrics(activity)
    t = ->(key) { I18n.t("activity.metric.#{key}") }
    metrics = []

    metrics << { label: t.("distance"), icon: "ruler",
                 value: "#{(activity.distance / 1000.0).round(2)} km" } if activity.distance

    metrics << { label: t.("moving_time"), icon: "clock",
                 value: duration_display(activity.active_time_duration) }

    metrics << { label: t.("elevation_gain"), icon: "mountain",
                 value: "#{activity.total_elevation_gain.to_i} m" } if activity.total_elevation_gain

    if activity.uses_pace?
      if (pace = activity.avg_pace_per_km)
        metrics << { label: t.("avg_pace"), icon: "gauge", value: pace_display(pace) }
      end
    elsif (avg = activity.avg_speed_kmh)
      metrics << { label: t.("avg_speed"), icon: "gauge", value: "#{avg.round(1)} km/h" }
    end

    if (max = activity.max_speed_kmh)
      metrics << { label: t.("max_speed"), icon: "gauge", value: "#{max.round(1)} km/h" }
    end

    if (hr = activity.avg_heart_rate)
      metrics << { label: t.("avg_heart_rate"), icon: "heart", value: "#{hr} bpm" }
    end
    if (hr = activity.max_heart_rate)
      metrics << { label: t.("max_heart_rate"), icon: "heart", value: "#{hr} bpm" }
    end

    if (power = activity.avg_power)
      metrics << { label: t.("avg_power"), icon: "zap", value: "#{power} W" }
    end
    if (power = activity.max_power)
      metrics << { label: t.("max_power"), icon: "zap", value: "#{power} W" }
    end

    if (cadence = activity.avg_cadence)
      metrics << { label: t.("avg_cadence"), icon: "activity",
                   value: "#{cadence} #{activity.uses_pace? ? 'spm' : 'rpm'}" }
    end

    metrics
  end
end
