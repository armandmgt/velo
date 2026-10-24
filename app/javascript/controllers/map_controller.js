import { Controller } from "@hotwired/stimulus"
import * as maplibregl from "maplibre-gl"
import { primaryAccentColor, resolveCssColor, FitToBoundsControl, styleUrl } from "controllers/lib/map_helpers"

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    route: Object,
  }

  #accentColor
  #marker
  #coordinates
  #styleReady = false
  #pendingStretch = null

  connect() {
    this.#accentColor = primaryAccentColor()

    // Compute initial bounds from route to avoid post-load zoom animation
    let initialBounds = null
    let initialGeojson = null

    if (this.hasRouteValue) {
      let route = this.routeValue
      if (typeof route === "string") {
        try { route = JSON.parse(route) } catch { route = null }
      }

      if (route && route.geometry && route.geometry.coordinates?.length) {
        // A non-owner's track arrives as a MultiLineString once its hidden
        // portion is cut out.
        const coords = route.geometry.type === "MultiLineString"
          ? route.geometry.coordinates.flat()
          : route.geometry.coordinates
        this.#coordinates = coords
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
      style: styleUrl(),
    })

    this.map.addControl(new maplibregl.NavigationControl({
      visualizePitch: true,
      visualizeRoll: true,
      showZoom: true,
      showCompass: true,
    }))
    this.map.addControl(new FitToBoundsControl(initialBounds))

    this.map.on("click", ({ lngLat }) => this.dispatch("click", { detail: { lngLat: [ lngLat.lng, lngLat.lat ] } }))

    this.map.on("load", () => {
      this.#styleReady = true
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
          "line-color": this.#accentColor,
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

      if (this.#pendingStretch) this.highlightStretch(...this.#pendingStretch)
    })
  }

  disconnect() {
    this.#marker?.remove()
    this.#marker = undefined
    this.map?.remove()
    this.map = undefined
  }

  // Outlet API: move a marker to the given [lng, lat] (used by the charts to
  // highlight the route position under the hovered data point).
  showPoint(coordinate) {
    if (!this.map) return
    if (!coordinate) return this.hidePoint()

    if (!this.#marker) {
      const el = document.createElement("div")
      el.style.width = "14px"
      el.style.height = "14px"
      el.style.borderRadius = "9999px"
      el.style.background = this.#accentColor
      el.style.border = "2px solid #ffffff"
      el.style.boxShadow = "0 0 0 1px rgba(0, 0, 0, 0.25)"
      this.#marker = new maplibregl.Marker({ element: el })
    }

    this.#marker.setLngLat(coordinate).addTo(this.map)
  }

  hidePoint() {
    this.#marker?.remove()
  }

  // Outlet API: draw the route vertices [startIndex..endIndex] over the route
  // (a best effort's stretch) and, unless `fit` is false, frame them.
  highlightStretch(startIndex, endIndex, { fit = true } = {}) {
    const coordinates = this.#coordinates?.slice(startIndex, endIndex + 1)
    if (!this.map || !coordinates || coordinates.length < 2) return
    this.element.dataset.highlightedStretch = `${startIndex}-${endIndex}`
    if (!this.#styleReady) {
      this.#pendingStretch = [ startIndex, endIndex, { fit } ]
      return
    }

    const data = { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates } }
    const source = this.map.getSource("stretch")
    if (source) {
      source.setData(data)
    } else {
      const secondary = getComputedStyle(document.documentElement).getPropertyValue("--color-secondary").trim()
      this.map.addSource("stretch", { type: "geojson", data })
      this.map.addLayer({
        id: "stretch-line",
        type: "line",
        source: "stretch",
        layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": resolveCssColor(secondary) || "#f97316", "line-width": 6 },
      })
    }

    if (!fit) return
    const bounds = coordinates.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(coordinates[0], coordinates[0])
    )
    this.map.fitBounds(bounds, { padding: 60, maxZoom: 16 })
  }

  clearStretch() {
    this.#pendingStretch = null
    delete this.element.dataset.highlightedStretch
    this.map?.getSource("stretch")?.setData({ type: "FeatureCollection", features: [] })
  }
}
