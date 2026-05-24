import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"

class FitToRouteControl {
  constructor(bounds) {
    this._bounds = bounds
  }

  onAdd(map) {
    this._map = map

    const span = document.createElement("span")
    span.className = "maplibregl-ctrl-icon"

    const button = document.createElement("button")
    button.className = "maplibregl-ctrl-geolocate"
    button.ariaLabel = "Back to center"
    button.addEventListener("click", () => {
      this._map.fitBounds(this._bounds, { padding: 40 })
    })
    button.appendChild(span)

    this._container = document.createElement("div")
    this._container.className = "maplibregl-ctrl maplibregl-ctrl-group"
    this._container.appendChild(button)

    return this._container
  }

  onRemove() {
    this._container.remove()
    this._map = undefined
  }
}

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    route: Object,
  }

  connect() {
    // Read primary color from CSS variable (supports oklch -> convert to rgb)
    const rawColor = getComputedStyle(document.documentElement)
      .getPropertyValue("--color-primary")
      .trim()

    const cssColor = this._resolveColor(rawColor) || "#ff0000"
    this._accentColor = cssColor
    // Compute initial bounds from route to avoid post-load zoom animation
    let initialBounds = null
    let initialGeojson = null

    if (this.hasRouteValue) {
      let route = this.routeValue
      if (typeof route === "string") {
        try { route = JSON.parse(route) } catch { route = null }
      }

      if (route && route.geometry && route.geometry.coordinates?.length) {
        const coords = route.geometry.coordinates
        initialGeojson = { type: "FeatureCollection", features: [route] }
        initialBounds = coords.reduce(
          (b, c) => b.extend(c),
          new maplibregl.LngLatBounds(coords[0], coords[0])
        )
      }
    }

    this.map = new maplibregl.Map({
      container: this.element,
      center: initialBounds ? undefined : [this.lngValue, this.latValue],
      zoom: initialBounds ? undefined : 13,
      bounds: initialBounds || undefined,
      fitBoundsOptions: initialBounds ? { padding: 40 } : undefined,
      style: "https://api.maptiler.com/maps/streets/style.json?key=" + (window.MAPTILER_API_KEY || ""),
    })

    this.map.addControl(new maplibregl.NavigationControl({
      visualizePitch: true,
      visualizeRoll: true,
      showZoom: true,
      showCompass: true,
    }))
    this.map.addControl(new FitToRouteControl(initialBounds))

    this.map.on("load", () => {
      if (!this.hasRouteValue) return

      const geojson = initialGeojson || {
        type: "FeatureCollection",
        features: [this.routeValue],
      }

      this.map.addSource("route", {
        type: "geojson",
        data: geojson,
      })

      this.map.addLayer({
        id: "geojson-line",
        type: "line",
        source: "route",
        paint: {
          "line-color": cssColor,
          "line-width": 3,
        },
      })
      // Add a thin casing (border) under the route like Strava
      this.map.addLayer({
        id: "geojson-line-casing",
        type: "line",
        source: "route",
        paint: {
          "line-color": "#ffffff",
          "line-width": 5,
          "line-opacity": 0.9
        }
      }, "geojson-line")
    })
  }

  disconnect() {
    this._marker?.remove()
    this._marker = undefined
    this.map?.remove()
    this.map = undefined
  }

  // Outlet API: move a marker to the given [lng, lat] (used by the charts to
  // highlight the route position under the hovered data point).
  showPoint(coordinate) {
    if (!this.map || !coordinate) return

    if (!this._marker) {
      const el = document.createElement("div")
      el.style.width = "14px"
      el.style.height = "14px"
      el.style.borderRadius = "9999px"
      el.style.background = this._accentColor
      el.style.border = "2px solid #ffffff"
      el.style.boxShadow = "0 0 0 1px rgba(0, 0, 0, 0.25)"
      this._marker = new maplibregl.Marker({ element: el })
    }

    this._marker.setLngLat(coordinate).addTo(this.map)
  }

  hidePoint() {
    this._marker?.remove()
  }

  _resolveColor(color) {
    if (!color) return null

    // Use canvas to normalize color (oklch -> rgb)
    const canvas = document.createElement("canvas")
    const ctx = canvas.getContext("2d")
    if (!ctx) return null

    try {
      ctx.fillStyle = "#000" // reset
      ctx.fillStyle = color
      return ctx.fillStyle // normalized rgb/hex
    } catch {
      return null
    }
  }
}
