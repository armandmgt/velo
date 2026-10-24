import { Controller } from "@hotwired/stimulus"
import * as maplibregl from "maplibre-gl"
import { primaryAccentColor, FitToBoundsControl, styleUrl } from "controllers/lib/map_helpers"

// Owner's activity paths as vector tiles. Each path is drawn semi-transparent,
// so routes ridden many times build up into brighter lines.
export default class extends Controller {
  static values = {
    tilesUrl: String,
    bounds: Array,
    maxZoom: { type: Number, default: 14 },
  }

  #map
  #fitControl

  connect() {
    const bounds = this.#bounds

    this.#map = new maplibregl.Map({
      container: this.element,
      style: styleUrl(),
      bounds: bounds ?? undefined,
      fitBoundsOptions: { padding: 40, maxZoom: 13 },
      center: bounds ? undefined : [2.35, 46.6],
      zoom: bounds ? undefined : 5,
    })

    this.#map.addControl(new maplibregl.NavigationControl({ showCompass: false }))
    this.#fitControl = new FitToBoundsControl(bounds)
    this.#map.addControl(this.#fitControl)
    this.#map.on("load", () => this.#addPaths())
  }

  disconnect() {
    this.#map?.remove()
    this.#map = undefined
  }

  // Changing a filter re-renders this page as a Turbo morph, which would strip
  // the map's canvas. Keep the map and take the new filter's values instead.
  keepMap(event) {
    if (event.target !== this.element) return

    event.preventDefault()
    for (const { name, value } of event.detail.newElement.attributes) {
      if (name.startsWith("data-heatmap-")) this.element.setAttribute(name, value)
    }
  }

  tilesUrlValueChanged(url) {
    this.#map?.getSource("heatmap")?.setTiles([url])
  }

  boundsValueChanged() {
    const bounds = this.#bounds
    this.#fitControl?.setBounds(bounds)
    if (bounds) this.#map?.fitBounds(bounds, { padding: 40, maxZoom: 13 })
  }

  get #bounds() {
    return this.boundsValue.length === 2 ? this.boundsValue : null
  }

  #addPaths() {
    this.#map.addSource("heatmap", {
      type: "vector",
      tiles: [this.tilesUrlValue],
      minzoom: 0,
      maxzoom: this.maxZoomValue,
    })

    this.#map.addLayer({
      id: "heatmap-paths",
      type: "line",
      source: "heatmap",
      "source-layer": "paths",
      layout: { "line-join": "round", "line-cap": "round" },
      paint: {
        "line-color": primaryAccentColor(),
        "line-opacity": ["interpolate", ["linear"], ["zoom"], 4, 0.2, 10, 0.35, 15, 0.5],
        "line-width": ["interpolate", ["exponential", 1.5], ["zoom"], 4, 1, 10, 2, 16, 4],
      },
    })
  }
}
