import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { primaryAccentColor, FitToBoundsControl, styleUrl } from "controllers/lib/map_helpers"

const PREVIEW_DEBOUNCE_MS = 200

export default class extends Controller {
  static values = {
    previewUrl: String,
    initialLng: { type: Number, default: 2.3522 },   // Paris fallback
    initialLat: { type: Number, default: 48.8566 },
  }

  static targets = [
    "sportSelect",
    "waypointsField",
    "distance",
    "elevationGain",
    "submit",
    "hint",
    "error",
    "clear",
    "undo",
  ]

  connect() {
    this._waypoints = []
    this._waypointMarkers = []
    this._accentColor = primaryAccentColor()
    this._fitControl = new FitToBoundsControl(null)

    this.map = new maplibregl.Map({
      container: this.element.querySelector("[data-route-planner-map]"),
      center: [ this.initialLngValue, this.initialLatValue ],
      zoom: 12,
      style: styleUrl(),
    })

    this.map.addControl(new maplibregl.NavigationControl({
      visualizePitch: true,
      visualizeRoll: true,
      showZoom: true,
      showCompass: true,
    }))
    this.map.addControl(this._fitControl)

    this.map.on("load", () => {
      this.map.addSource("route", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      })

      this.map.addLayer({
        id: "geojson-line-casing",
        type: "line",
        source: "route",
        paint: { "line-color": "#ffffff", "line-width": 5, "line-opacity": 0.9 },
      })

      this.map.addLayer({
        id: "geojson-line",
        type: "line",
        source: "route",
        paint: { "line-color": this._accentColor, "line-width": 3 },
      })
    })

    this.map.on("click", (e) => this._addWaypoint([ e.lngLat.lng, e.lngLat.lat ]))

    if (this.hasSportSelectTarget) {
      this.sportSelectTarget.addEventListener("change", () => this._schedulePreview())
    }
    if (this.hasClearTarget) {
      this.clearTarget.addEventListener("click", (e) => { e.preventDefault(); this.clear() })
    }
    if (this.hasUndoTarget) {
      this.undoTarget.addEventListener("click", (e) => { e.preventDefault(); this.undo() })
    }

    this._updateUI()
  }

  disconnect() {
    this._waypointMarkers.forEach((m) => m.remove())
    this._waypointMarkers = []
    this.map?.remove()
    this.map = undefined
    if (this._previewTimer) clearTimeout(this._previewTimer)
  }

  clear() {
    this._waypoints = []
    this._waypointMarkers.forEach((m) => m.remove())
    this._waypointMarkers = []
    this._setRouteGeojson({ type: "FeatureCollection", features: [] })
    this._fitControl.setBounds(null)
    this._updateStats(null, null)
    this._updateUI()
  }

  undo() {
    if (this._waypoints.length === 0) return
    this._removeWaypointAt(this._waypoints.length - 1)
  }

  _addWaypoint(lngLat) {
    this._waypoints.push(lngLat)
    const marker = this._buildMarker(lngLat, this._waypoints.length)
    marker.getElement().addEventListener("contextmenu", (e) => {
      e.preventDefault()
      const idx = this._waypointMarkers.indexOf(marker)
      if (idx === -1) return
      this._removeWaypointAt(idx)
    })
    marker.addTo(this.map)
    this._waypointMarkers.push(marker)
    this._updateUI()
    this._schedulePreview()
  }

  _removeWaypointAt(idx) {
    this._waypoints.splice(idx, 1)
    this._waypointMarkers[idx].remove()
    this._waypointMarkers.splice(idx, 1)
    this._waypointMarkers.forEach((m, i) => {
      m.getElement().textContent = String(i + 1)
    })
    this._updateUI()
    this._schedulePreview()
  }

  _buildMarker(lngLat, index) {
    const el = document.createElement("div")
    el.style.width = "26px"
    el.style.height = "26px"
    el.style.borderRadius = "9999px"
    el.style.background = this._accentColor
    el.style.color = "#ffffff"
    el.style.fontWeight = "700"
    el.style.fontSize = "13px"
    el.style.display = "flex"
    el.style.alignItems = "center"
    el.style.justifyContent = "center"
    el.style.border = "2px solid #ffffff"
    el.style.boxShadow = "0 1px 4px rgba(0, 0, 0, 0.3)"
    el.style.cursor = "pointer"
    el.textContent = String(index)
    return new maplibregl.Marker({ element: el }).setLngLat(lngLat)
  }

  _schedulePreview() {
    if (this._previewTimer) clearTimeout(this._previewTimer)
    this._previewTimer = setTimeout(() => this._fetchPreview(), PREVIEW_DEBOUNCE_MS)
  }

  async _fetchPreview() {
    if (this._waypoints.length < 2) {
      this._setRouteGeojson({ type: "FeatureCollection", features: [] })
      this._updateStats(null, null)
      return
    }

    const sport = this.hasSportSelectTarget ? this.sportSelectTarget.value : null
    if (!sport) return

    this._setError(null)

    try {
      const csrf = document.querySelector("meta[name='csrf-token']")?.content || ""
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept":       "application/json",
          "X-CSRF-Token": csrf,
        },
        body: JSON.stringify({ sport, waypoints: this._waypoints }),
      })

      if (!response.ok) {
        const payload = await response.json().catch(() => ({}))
        this._setError(payload.error || "routing_failed")
        return
      }

      const data = await response.json()
      this._setRouteGeojson({ type: "FeatureCollection", features: [ data.geojson ] })
      this._setFitBounds(data.geojson)
      this._updateStats(data.distance_meters, data.elevation_gain_meters)
    } catch (err) {
      console.error(err)
      this._setError("routing_failed")
    }
  }

  _setRouteGeojson(geojson) {
    const source = this.map?.getSource("route")
    if (source) source.setData(geojson)
  }

  _setFitBounds(feature) {
    const coords = feature?.geometry?.coordinates
    if (!coords?.length) return
    const bounds = coords.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(coords[0], coords[0])
    )
    this._fitControl.setBounds(bounds)
  }

  _updateStats(distanceMeters, elevationGainMeters) {
    if (this.hasDistanceTarget) {
      this.distanceTarget.textContent = distanceMeters != null
        ? `${(distanceMeters / 1000).toFixed(2)} km`
        : "—"
    }
    if (this.hasElevationGainTarget) {
      this.elevationGainTarget.textContent = elevationGainMeters != null
        ? `${Math.round(elevationGainMeters)} m`
        : "—"
    }
  }

  _setError(code) {
    if (!this.hasErrorTarget) return
    if (!code) {
      this.errorTarget.classList.add("hidden")
      this.errorTarget.textContent = ""
      return
    }
    const message = this.errorTarget.dataset[`${code.replace(/[-_](\w)/g, (_, c) => c.toUpperCase())}Message`] ||
                    this.errorTarget.dataset.defaultMessage ||
                    "Routing failed."
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  _updateUI() {
    if (this.hasWaypointsFieldTarget) {
      this.waypointsFieldTarget.value = JSON.stringify(this._waypoints)
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = this._waypoints.length < 2
    }
    if (this.hasHintTarget) {
      this.hintTarget.classList.toggle("hidden", this._waypoints.length > 0)
    }
    if (this.hasClearTarget) {
      this.clearTarget.classList.toggle("hidden", this._waypoints.length === 0)
    }
    if (this.hasUndoTarget) {
      this.undoTarget.classList.toggle("hidden", this._waypoints.length === 0)
    }
  }
}
