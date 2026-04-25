module ActivityCharts
  extend ActiveSupport::Concern

  included do
    def chart_data
      data_points = activity_data_points.order(:recorded_at).to_a
      {
        labels: data_points.pluck(:recorded_at),
        datasets: [
          {
            label: 'Speed',
            backgroundColor: '#3B82F6',
            data: data_points.pluck(:speed).map { _1 && _1 * 3.6 },
            tooltipFormatter: { unit: "km/h" }
          },
          {
            label: 'Cadence',
            backgroundColor: '#10B981',
            data: data_points.pluck(:cadence),
            tooltipFormatter: { unit: "rpm" },
            hidden: true
          },
          {
            label: 'Power',
            backgroundColor: '#F59E0B',
            data: data_points.pluck(:power),
            tooltipFormatter: { unit: "W" },
            hidden: true
          },
          {
            label: 'Heart rate',
            backgroundColor: '#EF4444',
            data: data_points.pluck(:heart_rate),
            tooltipFormatter: { unit: "bpm" },
            hidden: true
          }
        ]
      }
    end
  end
end
