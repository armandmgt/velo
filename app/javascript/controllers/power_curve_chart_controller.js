import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const ALL_TIME_COLOR = "#3B82F6"
const COMPARED_COLOR = "#EC4899"
const TICKS = [1, 5, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600, 7200, 14400, 21600]

function durationLabel(seconds) {
  if (seconds < 60) return `${seconds} s`
  if (seconds < 3600) return `${Math.round(seconds / 60)} min`
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.round((seconds % 3600) / 60)
  return minutes ? `${hours} h ${String(minutes).padStart(2, "0")}` : `${hours} h`
}

// Best average power by duration on a log time axis: the all-time envelope
// against the selected comparison period.
//
// Changing the period morphs the page in place, so the canvas is permanent (a
// morph would strip Chart.js's sizing) and new data updates the live chart.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { data: Object, labels: Object }

  #chart

  connect() {
    this.#chart = new Chart(this.canvasTarget.getContext("2d"), {
      type: "line",
      data: { datasets: this.#datasets },
      options: this.#options,
    })
  }

  disconnect() {
    this.#chart?.destroy()
    this.#chart = undefined
  }

  dataValueChanged() {
    this.#refresh()
  }

  labelsValueChanged() {
    this.#refresh()
  }

  #refresh() {
    if (!this.#chart) return

    this.#chart.data.datasets = this.#datasets
    this.#chart.update()
  }

  get #datasets() {
    return [
      this.#line(this.labelsValue.all_time, this.dataValue.all_time, ALL_TIME_COLOR),
      this.#line(this.labelsValue.compared, this.dataValue.compared, COMPARED_COLOR, { borderDash: [4, 3] }),
    ]
  }

  #line(label, data, color, extra = {}) {
    return { label, data, borderColor: color, backgroundColor: color, borderWidth: 2, pointRadius: 0, pointHoverRadius: 3, ...extra }
  }

  get #options() {
    return {
      responsive: true,
      maintainAspectRatio: false,
      parsing: false,
      interaction: { mode: "x", intersect: false },
      plugins: {
        legend: { position: "bottom", labels: { usePointStyle: true, boxHeight: 6 } },
        tooltip: {
          callbacks: {
            title: (items) => durationLabel(items[0].parsed.x),
            label: (item) => `${item.dataset.label} : ${item.parsed.y} W`,
          },
        },
      },
      scales: {
        x: {
          type: "logarithmic",
          min: 1,
          afterBuildTicks: (axis) => {
            axis.ticks = TICKS.filter((value) => value <= axis.max).map((value) => ({ value }))
          },
          ticks: { autoSkip: false, maxRotation: 0, callback: (value) => durationLabel(value) },
          grid: { color: "rgba(127,127,127,0.12)" },
        },
        y: { beginAtZero: true, ticks: { callback: (value) => `${value} W` } },
      },
    }
  }
}
