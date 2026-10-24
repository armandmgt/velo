module GearsHelper
  def gear_km(meters)
    number_with_delimiter((meters.to_f / 1000).round)
  end

  # "Chaîne — 1 840 / 3 000 km"
  def component_progress_label(component)
    "#{component.name} — #{gear_km(component.distance)} / #{number_with_delimiter(component.service_interval_km)} km"
  end

  def component_progress_class(component)
    { ok: "progress-primary", warning: "progress-warning", overdue: "progress-error" }.fetch(component.status)
  end

  def gear_icon_name(gear)
    gear.bike? ? "bike" : "sport-shoe"
  end

  def gear_default_sports_label(gear)
    gear.default_sports.map { |sport| t("activity.sport.#{sport}") }.to_sentence
  end

  # Everything the picker can offer, so `gear-picker` can refilter when the
  # sport changes. The activity's own gear stays listed even once retired:
  # dropping it from the options would unassign it on the next save.
  def gear_picker_catalogue(activity)
    gears = Current.user.gears.active.includes(:gear_defaults).order(:name).to_a
    gears << activity.gear if activity.gear&.retired?
    gears.map do |gear|
      { id: gear.id, name: gear_option_label(gear), kind: gear.kind, defaultSports: gear.default_sports }
    end
  end

  def gear_option_label(gear)
    gear.retired? ? "#{gear.name} (retiré)" : gear.name
  end

  def gear_picker_kinds
    Activity.sports.keys.index_with { |sport| Gear.kind_for_sport(sport) }.compact
  end
end
