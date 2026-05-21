import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static values = { data: Object }

  connect() {
    const { labels, data } = this.dataValue

    this.chart = new Chart(this.element.getContext("2d"), {
      type: "line",
      data: {
        labels,
        datasets: [{
          data,
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
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ctx.parsed.y !== null
                ? `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(ctx.parsed.y)} m`
                : "",
              title: (items) => {
                const start = new Date(labels[0])
                const elapsed = new Date(items[0].label) - start
                const hours = Math.floor(elapsed / 3_600_000)
                const minutes = Math.floor((elapsed % 3_600_000) / 60_000)
                const seconds = Math.floor((elapsed % 60_000) / 1_000)
                return new Intl.DurationFormat(undefined, { style: "narrow" }).format({ hours, minutes, seconds })
              },
            },
          },
        },
        scales: {
          x: {
            ticks: {
              callback(_value, index) {
                const start = new Date(labels[0])
                const elapsed = new Date(labels[index]) - start
                const hours = Math.floor(elapsed / 3_600_000)
                const minutes = Math.floor((elapsed % 3_600_000) / 60_000)
                const seconds = Math.floor((elapsed % 60_000) / 1_000)
                return new Intl.DurationFormat(undefined, { style: "narrow" }).format({ hours, minutes, seconds })
              },
            },
          },
          y: { ticks: { callback: (v) => `${v} m` } },
        },
      },
    })
  }

  disconnect() {
    this.chart?.destroy()
    this.chart = undefined
  }
}
