module ActivityCharts
  extend ActiveSupport::Concern

  included do
    def elevation_chart_data
      data_points = activity_data_points.order(:recorded_at).to_a
      altitudes = data_points.pluck(:altitude)
      return nil if altitudes.all?(&:nil?)

      {
        labels: data_points.pluck(:recorded_at),
        data: altitudes
      }
    end

    def chart_data(max_heart_rate: nil)
      data_points = activity_data_points.order(:recorded_at).to_a
      {
        labels: data_points.pluck(:recorded_at),
        # Parallel to labels/datasets: GPS coordinate per data point ([lng, lat]
        # or nil). Lets the chart map a hovered index back to a point on the map
        # — unlike `path`, which drops invalid points and loses index alignment.
        coordinates: data_points.map { |p| p.location ? [ p.location.x, p.location.y ] : nil },
        datasets: [
          {
            label: I18n.t("activity.chart.speed"),
            backgroundColor: "#3B82F6",
            data: data_points.pluck(:speed).map { _1 && _1 * 3.6 },
            tooltipFormatter: { unit: "km/h" }
          },
          {
            label: I18n.t("activity.chart.cadence"),
            backgroundColor: "#10B981",
            data: data_points.pluck(:cadence),
            tooltipFormatter: { unit: "rpm" },
            hidden: true
          },
          {
            label: I18n.t("activity.chart.power"),
            backgroundColor: "#F59E0B",
            data: data_points.pluck(:power),
            tooltipFormatter: { unit: "W" },
            hidden: true
          },
          {
            label: I18n.t("activity.chart.heart_rate"),
            backgroundColor: "#EF4444",
            data: data_points.pluck(:heart_rate),
            tooltipFormatter: { unit: "bpm" },
            hidden: true,
            **heart_rate_zone_dataset_options(max_heart_rate)
          }
        ]
      }
    end

    # When a max HR is known, hand the HR dataset the per-zone bpm boundaries and
    # colors so the chart can tint the line by zone (see activity_charts_controller).
    def heart_rate_zone_dataset_options(max_heart_rate)
      return {} unless max_heart_rate

      {
        zoneBoundaries: [ 0.6, 0.7, 0.8, 0.9 ].map { (_1 * max_heart_rate).round },
        zoneColors: ActivityHeartRateZones::HR_ZONES.map { _1[:color] }
      }
    end
  end
end
