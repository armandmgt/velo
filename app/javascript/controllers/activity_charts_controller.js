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

    ctx.restore()
  },
}

// Maps a heart-rate value to its zone color given the per-zone upper bpm
// boundaries. Values at/above the last boundary fall into the final zone.
function zoneColorFor(value, boundaries, colors) {
  if (value === null || value === undefined) return undefined
  const index = boundaries.findIndex(boundary => value < boundary)
  return colors[index === -1 ? colors.length - 1 : index]
}

// Formats elapsed time between two data-point timestamps as a narrow duration
// (e.g. "1h 5m 3s"). Shared by the x-axis ticks and the tooltip title so both
// read the same as the elevation profile's time axis.
function formatElapsed(startLabel, currentLabel) {
  const elapsed = new Date(currentLabel) - new Date(startLabel)
  if (!Number.isFinite(elapsed)) return ""
  const hours = Math.floor(elapsed / 3_600_000)
  const minutes = Math.floor((elapsed % 3_600_000) / 60_000)
  const seconds = Math.floor((elapsed % 60_000) / 1_000)
  return new Intl.DurationFormat(undefined, { style: "narrow" }).format({ hours, minutes, seconds })
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
  static outlets = ["map"]
  static values = {
    data: Object,
    coordinates: { type: Array, default: [] },
  }

  connect() {
    this.element_ = this.hasCanvasTarget ? this.canvasTarget : this.element

    this.chart = new Chart(this.element_.getContext("2d"), {
      type: "line",
      data: this.chartData,
      options: this.chartOptions,
      plugins: [
        verticalHoverLine,
      ],
    })

    this.hideMarker = () => this.hasMapOutlet && this.mapOutlet.hidePoint()
    this.element_.addEventListener("mouseleave", this.hideMarker)
  }

  disconnect() {
    this.element_?.removeEventListener("mouseleave", this.hideMarker)
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
        ...(dataset.zoneBoundaries && {
          segment: {
            borderColor: (ctx) =>
              zoneColorFor(ctx.p1.parsed.y, dataset.zoneBoundaries, dataset.zoneColors) || dataset.backgroundColor,
          },
        }),
        tooltip: {
          callbacks: {
            label: valueFormatter(dataset.tooltipFormatter.unit),
          },
        },
      })),
    }
  }

  get chartOptions() {
    return {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        mode: "index",
        intersect: false,
      },
      onHover: (_event, active) => {
        if (!this.hasMapOutlet) return

        if (active.length > 0) {
          const coordinate = this.coordinatesValue[active[0].index]
          if (coordinate) {
            this.mapOutlet.showPoint(coordinate)
            return
          }
        }
        this.mapOutlet.hidePoint()
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          position: "atCursor",
          callbacks: {
            title: (items) => {
              const labels = this.dataValue.labels
              const index = items[0]?.dataIndex ?? 0
              return formatElapsed(labels[0], labels[index])
            },
          },
        },
      },
      scales: {
        x: {
          ticks: {
            callback: function (_value, index, _ticks) {
              return formatElapsed(this.getLabelForValue(0), this.getLabelForValue(index))
            },
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
