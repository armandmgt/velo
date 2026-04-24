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
            borderColor: 'transparent',
            fill: true,
            pointStyle: false,
            tension: 0,
            data: data_points.pluck(:speed).map { _1 * 3.6 }
          }
        ]
      }
    end

    def chart_options
      {
        responsive: true,
        interaction: {
          mode: 'index',
          intersect: false
        },
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            position: 'atCursor',
            callbacks: {
              label: "chartSpeedFormatter"
            }
          }
        },
        scales: {
          x: {
            type: 'time',
          },
          y: {}
        }
      }
    end
  end
end
