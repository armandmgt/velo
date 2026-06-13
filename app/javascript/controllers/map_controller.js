import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { primaryAccentColor, FitToBoundsControl, styleUrl } from "controllers/lib/map_helpers"

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    route: Object,
  }

  connect() {
    this._accentColor = primaryAccentColor()

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
      style: styleUrl(),
    })

    this.map.addControl(new maplibregl.NavigationControl({
      visualizePitch: true,
      visualizeRoll: true,
      showZoom: true,
      showCompass: true,
    }))
    this.map.addControl(new FitToBoundsControl(initialBounds))

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
          "line-color": this._accentColor,
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
}
