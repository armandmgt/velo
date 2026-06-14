import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static values = {
    data: { type: Object, default: {} },
    coordinates: { type: Array, default: [] },
    xMode: { type: String, default: "time" },
  }

  static outlets = [ "map", "route-planner" ]

  connect() {
    this._buildChart(this.dataValue)

    this._onMouseLeave = () => this._hideHighlight()
    this.element.addEventListener("mouseleave", this._onMouseLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseleave", this._onMouseLeave)
    this.chart?.destroy()
    this.chart = undefined
  }

  // --- public API used by route_planner_controller via outlet ---

  updateData(data, coordinates) {
    this.coordinatesValue = coordinates || []
    if (!data?.labels?.length) {
      this.clear()
      return
    }

    if (this.chart) {
      this.chart.data.labels = data.labels
      this.chart.data.datasets[0].data = data.data
      this.chart.update("none")
      this.element.classList.remove("hidden")
      return
    }

    this._buildChart(data)
    this.element.classList.remove("hidden")
  }

  clear() {
    this.coordinatesValue = []
    if (this.chart) {
      this.chart.data.labels = []
      this.chart.data.datasets[0].data = []
      this.chart.update("none")
    }
    this.element.classList.add("hidden")
  }

  // --- chart ---

  _buildChart(data) {
    if (!data?.labels?.length) return

    this.chart = new Chart(this.element.getContext("2d"), {
      type: "line",
      data: {
        labels: data.labels,
        datasets: [{
          data: data.data,
          borderColor: "#10B981",
          backgroundColor: "rgba(16, 185, 129, 0.15)",
          borderWidth: 1.5,
          fill: true,
          pointStyle: false,
          tension: 0.3,
          spanGaps: true,
        }],
      },
      options: {
        animation: false,
        interaction: { mode: "index", intersect: false },
        onHover: (_event, active) => this._onHover(active),
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ctx.parsed.y !== null
                ? `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(ctx.parsed.y)} m`
                : "",
              title: (items) => this._formatX(items[0]?.label, items[0]?.dataIndex),
            },
          },
        },
        scales: {
          x: {
            ticks: {
              callback: (_value, index) =>
                this._formatX(this.chart?.data.labels[index], index),
            },
          },
          y: { ticks: { callback: (v) => `${v} m` } },
        },
      },
    })
  }

  _formatX(rawLabel, _index) {
    if (rawLabel == null) return ""
    if (this.xModeValue === "distance") {
      const meters = Number(rawLabel)
      if (!Number.isFinite(meters)) return ""
      return `${(meters / 1000).toLocaleString(undefined, { maximumFractionDigits: 1 })} km`
    }

    const labels = this.chart?.data.labels
    if (!labels?.length) return ""
    const start = new Date(labels[0])
    const elapsed = new Date(rawLabel) - start
    if (!Number.isFinite(elapsed)) return ""
    const hours   = Math.floor(elapsed / 3_600_000)
    const minutes = Math.floor((elapsed % 3_600_000) / 60_000)
    const seconds = Math.floor((elapsed % 60_000) / 1_000)
    return new Intl.DurationFormat(undefined, { style: "narrow" }).format({ hours, minutes, seconds })
  }

  _onHover(active) {
    const target = this._hoverTarget()
    if (!target) return

    if (active.length > 0) {
      const coordinate = this.coordinatesValue[active[0].index]
      if (coordinate) {
        target.showPoint?.(coordinate)
        return
      }
    }
    target.hidePoint?.()
  }

  _hideHighlight() {
    this._hoverTarget()?.hidePoint?.()
  }

  _hoverTarget() {
    if (this.hasMapOutlet) return this.mapOutlet
    if (this.hasRoutePlannerOutlet) return this.routePlannerOutlet
    return null
  }
}
