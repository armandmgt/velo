module HeatmapsHelper
  # MapLibre substitutes {z}/{x}/{y}, which URL helpers would percent-encode.
  def heatmap_tiles_url_template(heatmap)
    query = heatmap.filter_params.to_query
    "#{heatmap_url}/tiles/{z}/{x}/{y}#{"?#{query}" if query.present?}"
  end

  def heatmap_sport_options(heatmap)
    options = [ [ t("heatmap.filters.all_sports"), "" ] ] +
      Heatmap::SPORT_CATEGORIES.map { |category| [ t("activity.sport_group.#{category}"), category ] }
    options_for_select(options, heatmap.sport_category.to_s)
  end

  def heatmap_period_options(heatmap, years)
    options = [ [ t("heatmap.filters.all_time"), "" ] ] +
      years.map { |year| [ year.to_s, year.to_s ] } +
      [ [ t("heatmap.filters.custom"), Heatmap::CUSTOM_PERIOD ] ]
    options_for_select(options, heatmap.period.to_s)
  end
end
