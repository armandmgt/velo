module ApplicationHelper
  def sport_grouped_options(selected = nil)
    group_labels = {
      cycling: I18n.t("activity.sport_group.cycling"),
      running: I18n.t("activity.sport_group.running"),
      other:   I18n.t("activity.sport_group.other")
    }
    grouped = group_labels.transform_values { [] }
    Activity.sports.each_key do |key|
      category = Activity::SPORT_CATEGORY[key.to_sym]
      grouped[category] << [ I18n.t("activity.sport.#{key}"), key ]
    end
    grouped_options_for_select(
      grouped.map { |cat, options| [ group_labels[cat], options ] },
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
end
