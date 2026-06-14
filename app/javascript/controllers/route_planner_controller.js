import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { primaryAccentColor, FitToBoundsControl, styleUrl } from "controllers/lib/map_helpers"

const PREVIEW_DEBOUNCE_MS = 200

export default class extends Controller {
  static values = {
    previewUrl: String,
    initialLng: { type: Number, default: 2.3522 },   // Paris fallback
    initialLat: { type: Number, default: 48.8566 },
    initialWaypoints: { type: Array, default: [] },
  }

  static targets = [
    "sportSelect",
    "waypointsField",
    "distance",
    "elevationGain",
    "submit",
    "hint",
    "error",
    "errorMessage",
    "retry",
    "clear",
    "undo",
  ]

  static outlets = [ "elevation-profile" ]

  connect() {
    this._waypoints = []
    this._waypointMarkers = []
    this._routeCoordinates = []
    this._accentColor = primaryAccentColor()
    this._fitControl = new FitToBoundsControl(null)
    this._highlightMarker = null

    this.map = new maplibregl.Map({
      container: this.element.querySelector("[data-route-planner-map]"),
      center: this._initialCenter(),
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

      this._hydrateInitialWaypoints()
    })

    this.map.on("click", (e) => this._handleMapClick(e))

    if (this.hasSportSelectTarget) {
      this.sportSelectTarget.addEventListener("change", () => this._schedulePreview())
    }
    if (this.hasClearTarget) {
      this.clearTarget.addEventListener("click", (e) => { e.preventDefault(); this.clear() })
    }
    if (this.hasUndoTarget) {
      this.undoTarget.addEventListener("click", (e) => { e.preventDefault(); this.undo() })
    }
    if (this.hasRetryTarget) {
      this.retryTarget.addEventListener("click", (e) => { e.preventDefault(); this._fetchPreview() })
    }

    this._updateUI()
  }

  disconnect() {
    this._waypointMarkers.forEach((m) => m.remove())
    this._waypointMarkers = []
    this._highlightMarker?.remove()
    this._highlightMarker = null
    this.map?.remove()
    this.map = undefined
    if (this._previewTimer) clearTimeout(this._previewTimer)
  }

  // Public — used by elevation_profile_controller via outlet.
  showPoint(coordinate) {
    if (!this.map || !coordinate) return
    if (!this._highlightMarker) {
      const el = document.createElement("div")
      el.style.width = "14px"
      el.style.height = "14px"
      el.style.borderRadius = "9999px"
      el.style.background = this._accentColor
      el.style.border = "2px solid #ffffff"
      el.style.boxShadow = "0 0 0 1px rgba(0, 0, 0, 0.25)"
      el.style.pointerEvents = "none"
      this._highlightMarker = new maplibregl.Marker({ element: el })
    }
    this._highlightMarker.setLngLat(coordinate).addTo(this.map)
  }

  hidePoint() {
    this._highlightMarker?.remove()
  }

  clear() {
    this._setWaypoints([])
    this._setRouteGeojson({ type: "FeatureCollection", features: [] })
    this._fitControl.setBounds(null)
    this._updateStats(null, null)
    this.elevationProfileOutlet?.clear?.()
  }

  undo() {
    if (this._waypoints.length === 0) return
    const next = this._waypoints.slice(0, -1)
    this._setWaypoints(next)
  }

  // --- waypoint mutation ---

  _setWaypoints(next) {
    this._waypoints = next.map((p) => [ p[0], p[1] ])

    this._waypointMarkers.forEach((m) => m.remove())
    this._waypointMarkers = this._waypoints.map((lngLat, i) => this._buildWaypointMarker(lngLat, i))

    this._updateUI()
    this._schedulePreview()
  }

  _addWaypoint(lngLat) {
    this._setWaypoints([ ...this._waypoints, lngLat ])
  }

  _removeWaypointAt(idx) {
    const next = this._waypoints.slice()
    next.splice(idx, 1)
    this._setWaypoints(next)
  }

  _moveWaypoint(idx, lngLat) {
    const next = this._waypoints.slice()
    next[idx] = lngLat
    this._setWaypoints(next)
  }

  _insertWaypointAt(idx, lngLat) {
    const next = this._waypoints.slice()
    next.splice(idx, 0, lngLat)
    this._setWaypoints(next)
  }

  _hydrateInitialWaypoints() {
    if (!this.hasInitialWaypointsValue) return
    const seeded = this.initialWaypointsValue
    if (!Array.isArray(seeded) || seeded.length === 0) return
    this._setWaypoints(seeded)
    const bounds = seeded.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(seeded[0], seeded[0])
    )
    this._fitControl.setBounds(bounds)
    this.map.fitBounds(bounds, { padding: 60, animate: false })
  }

  // --- marker construction ---

  _buildWaypointMarker(lngLat, index) {
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
    el.style.cursor = "grab"
    el.style.touchAction = "none"
    el.textContent = String(index + 1)

    const marker = new maplibregl.Marker({ element: el, draggable: true }).setLngLat(lngLat)

    marker.on("dragstart", () => {
      el.style.cursor = "grabbing"
      this._suppressMapClickUntil = Date.now() + 250
    })
    marker.on("dragend", () => {
      el.style.cursor = "grab"
      const i = this._waypointMarkers.indexOf(marker)
      if (i === -1) return
      const ll = marker.getLngLat()
      this._moveWaypoint(i, [ ll.lng, ll.lat ])
    })

    el.addEventListener("contextmenu", (e) => {
      e.preventDefault()
      const i = this._waypointMarkers.indexOf(marker)
      if (i !== -1) this._removeWaypointAt(i)
    })
    el.addEventListener("dblclick", (e) => {
      e.preventDefault()
      e.stopPropagation()
      const i = this._waypointMarkers.indexOf(marker)
      if (i !== -1) this._removeWaypointAt(i)
    })

    marker.addTo(this.map)
    return marker
  }

  // --- map click → add or insert ---

  _handleMapClick(e) {
    if (this._suppressMapClickUntil && Date.now() < this._suppressMapClickUntil) return

    const hits = this.map.queryRenderedFeatures(e.point, { layers: [ "geojson-line" ] })
    const lngLat = [ e.lngLat.lng, e.lngLat.lat ]

    if (hits.length > 0 && this._waypoints.length >= 2 && this._routeCoordinates.length >= 2) {
      const idx = this._insertionIndexFor(lngLat)
      this._insertWaypointAt(idx, lngLat)
      return
    }

    this._addWaypoint(lngLat)
  }

  // Map waypoints onto the routed polyline by nearest-index, then bracket the
  // click index between two waypoints — that's the insertion slot.
  _insertionIndexFor(clickLngLat) {
    const clickIdx = this._nearestRouteIndex(clickLngLat)
    const waypointIndices = this._waypoints.map((w) => this._nearestRouteIndex(w))

    for (let i = 0; i < waypointIndices.length - 1; i++) {
      if (clickIdx >= waypointIndices[i] && clickIdx <= waypointIndices[i + 1]) {
        return i + 1
      }
    }
    return this._waypoints.length
  }

  _nearestRouteIndex(lngLat) {
    let bestIdx = 0
    let bestDist = Infinity
    for (let i = 0; i < this._routeCoordinates.length; i++) {
      const c = this._routeCoordinates[i]
      const dx = c[0] - lngLat[0]
      const dy = c[1] - lngLat[1]
      const d  = dx * dx + dy * dy
      if (d < bestDist) {
        bestDist = d
        bestIdx  = i
      }
    }
    return bestIdx
  }

  // --- preview ---

  _schedulePreview() {
    if (this._previewTimer) clearTimeout(this._previewTimer)
    this._previewTimer = setTimeout(() => this._fetchPreview(), PREVIEW_DEBOUNCE_MS)
  }

  async _fetchPreview() {
    if (this._waypoints.length < 2) {
      this._routeCoordinates = []
      this._setRouteGeojson({ type: "FeatureCollection", features: [] })
      this._updateStats(null, null)
      this.elevationProfileOutlet?.clear?.()
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
      this._routeCoordinates = data.coordinates || data.geojson?.geometry?.coordinates || []
      this._setRouteGeojson({ type: "FeatureCollection", features: [ data.geojson ] })
      this._setFitBounds(data.geojson)
      this._updateStats(data.distance_meters, data.elevation_gain_meters)
      this._pushElevation(data.elevation_samples)
    } catch (err) {
      console.error(err)
      this._setError("routing_failed")
    }
  }

  _pushElevation(samples) {
    if (!this.hasElevationProfileOutlet) return
    if (!Array.isArray(samples) || samples.length === 0) {
      this.elevationProfileOutlet.clear?.()
      return
    }
    const labels = samples.map((s) => s[0])
    const data   = samples.map((s) => s[1])
    this.elevationProfileOutlet.updateData?.({ labels, data }, this._routeCoordinates)
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
      return
    }

    const ds = this.errorTarget.dataset
    const key = `${code.replace(/[-_](\w)/g, (_, c) => c.toUpperCase())}Message`
    const message = ds[key] || ds.defaultMessage || "Routing failed."

    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
    } else {
      this.errorTarget.textContent = message
    }
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

  _initialCenter() {
    if (this.hasInitialWaypointsValue && this.initialWaypointsValue.length > 0) {
      return this.initialWaypointsValue[0]
    }
    return [ this.initialLngValue, this.initialLatValue ]
  }
}
