import { Controller } from "@hotwired/stimulus"
import { Chart, registerables, Tooltip } from "chart.js"

Chart.register(...registerables)

Tooltip.positioners.atCursor = function (elements, eventPosition) {
  return eventPosition
}

const verticalHoverLine = {
  id: "verticalHoverLine",
  afterDatasetsDraw(chart, _args, _pluginOptions) {
    const { ctx, chartArea: { top, bottom } } = chart

    ctx.save()

    const visibleDatasetIndex = chart.data.datasets.findIndex((_, index) => chart.isDatasetVisible(index))
    chart.getDatasetMeta(visibleDatasetIndex).data.forEach(point => {
      if (point.active) {
        ctx.beginPath()
        ctx.strokeStyle = "black"
        ctx.moveTo(point.x, top)
        ctx.lineTo(point.x, bottom)
        ctx.stroke()
      }
    })
  },
}

function valueFormatter(unit) {
  return function (context) {
    let label = context.dataset.label || ""

    if (label) {
      label += ": "
    }
    if (context.parsed.y !== null) {
      label += new Intl.NumberFormat(undefined, {
        style: "decimal",
        maximumFractionDigits: 2,
      }).format(context.parsed.y)
      label += unit
    }
    return label
  }
}
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    data: Object,
  }

  connect() {
    const element = this.hasCanvasTarget ? this.canvasTarget : this.element

    this.chart = new Chart(element.getContext("2d"), {
      type: "line",
      data: this.chartData,
      options: this.chartOptions,
      plugins: [
        verticalHoverLine,
      ],
    })
  }

  disconnect() {
    this.chart.destroy()
    this.chart = undefined
  }

  get chartData() {
    if (!this.hasDataValue) {
      console.warn("[activity_charts] No data provided.")
    }

    return {
      labels: this.dataValue.labels,
      datasets: this.dataValue.datasets.map(dataset => ({
        ...dataset,
        borderColor: dataset.backgroundColor,
        borderWidth: 1,
        // fill: true,
        pointStyle: false,
        tension: 0.1,
        tooltip: {
          callbacks: {
            label: valueFormatter(dataset.tooltipFormatter.unit),
          },
        }
      })),
    }
  }

  get chartOptions() {
    return {
      responsive: true,
      interaction: {
        mode: "index",
        intersect: false,
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          position: "atCursor",
        },
      },
      scales: {
        x: {
          ticks: {
            callback: function (_value, index, _ticks) {
              const startTime = new Date(this.getLabelForValue(0))
              const endTime = new Date(this.getLabelForValue(index))
              const hours = Math.floor((endTime - startTime) / (1000 * 60 * 60))
              const minutes = Math.floor((endTime - startTime) / (1000 * 60)) % 60
              const seconds = Math.floor((endTime - startTime) / 1000) % 60
              return new Intl.DurationFormat(undefined, {
                style: "narrow",
              }).format({ hours, minutes, seconds })
            }
          },
        },
        y: {},
      },
    }

  }

  changeDataset(event) {
    const datasetIndex = parseInt(event.target.value)
    this.chart.data.datasets.forEach((dataset, i) => {
      dataset.hidden = i !== datasetIndex
    })
    this.chart.update()
  }
}
