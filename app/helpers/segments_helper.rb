module SegmentsHelper
  def segment_distance(segment)
    meters = segment.distance
    meters < 1_000 ? "#{meters.round} m" : "#{number_with_precision(meters / 1000.0, precision: 2)} km"
  end

  def segment_grade(segment)
    "#{number_with_precision(segment.average_grade, precision: 1)} %"
  end

  def segment_figures(segment)
    [ segment_distance(segment), "#{segment.elevation_gain.round} m D+", segment_grade(segment) ].join(" · ")
  end

  def segment_effort_private_tag(effort)
    return unless effort.private?

    tag.span("Privé", class: "badge badge-sm badge-outline",
                      title: "Compte pour vos records, mais pas pour le classement")
  end
end
