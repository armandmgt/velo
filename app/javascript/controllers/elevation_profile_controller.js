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

  #onMouseLeave

  connect() {
    this.#buildChart(this.dataValue)

    this.#onMouseLeave = () => this.#hideHighlight()
    this.element.addEventListener("mouseleave", this.#onMouseLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseleave", this.#onMouseLeave)
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

    this.#buildChart(data)
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

  #buildChart(data) {
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
        onHover: (_event, active) => this.#onHover(active),
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ctx.parsed.y !== null
                ? `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(ctx.parsed.y)} m`
                : "",
              title: (items) => this.#formatX(items[0]?.label, items[0]?.dataIndex),
            },
          },
        },
        scales: {
          x: {
            ticks: {
              callback: (_value, index) =>
                this.#formatX(this.chart?.data.labels[index], index),
            },
          },
          y: { ticks: { callback: (v) => `${v} m` } },
        },
      },
    })
  }

  #formatX(rawLabel, _index) {
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

  #onHover(active) {
    const target = this.#hoverTarget()
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

  #hideHighlight() {
    this.#hoverTarget()?.hidePoint?.()
  }

  #hoverTarget() {
    if (this.hasMapOutlet) return this.mapOutlet
    if (this.hasRoutePlannerOutlet) return this.routePlannerOutlet
    return null
  }
}
