import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const dateFormat = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short" })
const tooltipDateFormat = new Intl.DateTimeFormat("fr-FR", { weekday: "short", day: "numeric", month: "long", year: "numeric" })

// Labels are ISO dates; parsing them as local noon keeps the day stable in any
// browser time zone.
function parseDay(iso) {
  return new Date(`${iso}T12:00:00`)
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = { data: Object, labels: Object, colors: Object }

  #chart

  connect() {
    this.#chart = new Chart(this.canvasTarget.getContext("2d"), {
      type: "line",
      data: this.#chartData,
      options: this.#chartOptions,
    })
  }

  disconnect() {
    this.#chart?.destroy()
    this.#chart = undefined
  }

  get #chartData() {
    const { labels, load, fitness, fatigue, form } = this.dataValue
    const colors = this.colorsValue

    return {
      labels,
      datasets: [
        this.#line(this.labelsValue.fitness, fitness, colors.fitness, { fill: { target: "origin", above: `${colors.fitness}1A` } }),
        this.#line(this.labelsValue.fatigue, fatigue, colors.fatigue),
        this.#line(this.labelsValue.form, form, colors.form, { borderDash: [4, 3] }),
        {
          type: "bar",
          label: this.labelsValue.load,
          data: load,
          yAxisID: "load",
          backgroundColor: `${colors.load}59`,
          barPercentage: 1,
          categoryPercentage: 0.8,
          order: 10,
        },
      ],
    }
  }

  #line(label, data, color, extra = {}) {
    return {
      type: "line",
      label,
      data,
      yAxisID: "y",
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 0,
      pointHoverRadius: 3,
      tension: 0.2,
      ...extra,
    }
  }

  get #chartOptions() {
    return {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { position: "bottom", labels: { usePointStyle: true, boxHeight: 6 } },
        tooltip: {
          filter: (item) => item.parsed.y !== null,
          callbacks: {
            title: (items) => tooltipDateFormat.format(parseDay(this.dataValue.labels[items[0].dataIndex])),
            label: (item) => `${item.dataset.label} : ${Math.round(item.parsed.y)}`,
          },
        },
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            maxRotation: 0,
            autoSkipPadding: 16,
            callback: (_value, index) => dateFormat.format(parseDay(this.dataValue.labels[index])),
          },
        },
        y: { position: "left", grace: "5%" },
        load: { position: "right", beginAtZero: true, grid: { display: false } },
      },
    }
  }
}
