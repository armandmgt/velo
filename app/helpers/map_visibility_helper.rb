module MapVisibilityHelper
  def map_distance_label(metres)
    return "Désactivé" if metres.zero?
    return "#{metres} m" if metres < 1000

    "#{number_with_precision(metres / 1000.0, precision: 1, strip_insignificant_zeros: true, separator: ',')} km"
  end
end
