module BestEffortsHelper
  def best_effort_label(effort_or_key)
    key = effort_or_key.respond_to?(:distance) ? effort_or_key.distance : effort_or_key
    t("best_effort.distance.#{key}")
  end

  def best_effort_time(effort)
    total = effort.elapsed_seconds.round
    h, rest = total.divmod(3600)
    m, s = rest.divmod(60)
    h.positive? ? format("%d:%02d:%02d", h, m, s) : format("%d:%02d", m, s)
  end

  # Pace for the running category, speed for cycling.
  def best_effort_rate(effort, category)
    if category == :running
      pace_display(effort.elapsed_seconds / (effort.meters / 1000.0))
    else
      "#{(effort.speed * 3.6).round(1)} km/h"
    end
  end

  def best_effort_badge(rank)
    return unless rank

    tag.span(t("best_effort.rank.#{rank}"), title: t("best_effort.rank_title.#{rank}"),
             class: [ "badge badge-sm font-semibold", rank == 1 ? "badge-warning" : "badge-ghost" ])
  end
end
