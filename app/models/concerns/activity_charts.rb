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

    def chart_data
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
            hidden: true
          }
        ]
      }
    end
  end
end
