import { Controller } from "@hotwired/stimulus"
import { Chart, Tooltip, registerables } from "chart.js"
import "moment"
import "chartjs-adapter-moment"

Chart.register(...registerables)

Tooltip.positioners.atCursor = function(elements, eventPosition) {
  return eventPosition
}

const verticalHoverLine = {
  id: "verticalHoverLine",
  afterDatasetsDraw(chart, args, pluginOptions) {
    const { ctx, chartArea: { top, bottom, height }} = chart

    ctx.save()

    chart.getDatasetMeta(0).data.forEach(point => {
      if (point.active) {
        ctx.beginPath()
        ctx.strokeStyle = "black"
        ctx.moveTo(point.x, top)
        ctx.lineTo(point.x, bottom)
        ctx.stroke()
      }
    })
  }
}

function chartSpeedFormatter(context) {
  let label = context.dataset.label || ""

  if (label) {
    label += ": "
  }
  if (context.parsed.y !== null) {
    label += new Intl.NumberFormat(undefined, { style: "unit", unit: "kilometer", maximumFractionDigits: 2 }).format(context.parsed.y)
    label += "/h"
  }
  return label
}

const chartFunctions = {
  chartSpeedFormatter,
}

function resolveChartFunctions(obj) {
  if (obj == null || typeof obj !== "object") {
    return obj
  }

  const resolved = Array.isArray(obj) ? [] : {}

  for (const key in obj) {
    const value = obj[key]
    if (typeof value === "string" && chartFunctions[value]) {
      resolved[key] = chartFunctions[value]
    } else if (typeof value === "object") {
      resolved[key] = resolveChartFunctions(value)
    } else {
      resolved[key] = value
    }
  }

  return resolved
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    type: {
      type: String,
      default: "line",
    },
    data: Object,
    options: Object,
  }

  connect() {
    const element = this.hasCanvasTarget ? this.canvasTarget : this.element

    this.chart = new Chart(element.getContext("2d"), {
      type: this.typeValue,
      data: this.chartData,
      options: this.chartOptions,
      plugins: [
        verticalHoverLine,
      ]
    })
  }

  disconnect() {
    this.chart.destroy()
    this.chart = undefined
  }

  get chartData() {
    if (!this.hasDataValue) {
      console.warn("[@stimulus-components/chartjs] You need to pass data as JSON to see the chart.")
    }

    return this.dataValue
  }

  get chartOptions() {
    const resolved = resolveChartFunctions(this.optionsValue)
    return {
      ...this.defaultOptions,
      ...resolved,
    }
  }

  get defaultOptions() {
    return {}
  }
}
