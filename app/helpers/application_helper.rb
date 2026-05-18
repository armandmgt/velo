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
end
