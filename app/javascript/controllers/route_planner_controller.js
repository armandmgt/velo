import { Controller } from "@hotwired/stimulus"
import * as maplibregl from "maplibre-gl"
import { FitToBoundsControl, primaryAccentColor, styleUrl } from "controllers/lib/map_helpers"

const PREVIEW_DEBOUNCE_MS = 200
// Mirrors PlannedRoutesController::MAX_GPX_BYTES so an oversized file fails
// instantly instead of after a pointless upload.
const MAX_GPX_BYTES = 5 * 1024 * 1024

export default class extends Controller {
  static values = {
    previewUrl: String,
    importUrl: String,
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
    "clear",
    "undo",
    "redo",
    "gpxInput",
    "gpxBusy",
    "nameField",
    "retry",
  ]

  static outlets = [ "elevation-profile" ]

  #waypoints
  #waypointMarkers
  #routeCoordinates
  #history
  #redoStack
  #historyLimit
  #accentColor
  #fitControl
  #highlightMarker
  #previewTimer
  #suppressMapClickUntil

  connect() {
    this.#waypoints = []
    this.#waypointMarkers = []
    this.#routeCoordinates = []
    this.#history = []
    this.#redoStack = []
    this.#historyLimit = 50
    this.#accentColor = primaryAccentColor()
    this.#fitControl = new FitToBoundsControl(null)
    this.#highlightMarker = null

    this.map = new maplibregl.Map({
      container: this.element.querySelector("[data-route-planner-map]"),
      center: this.#initialCenter(),
      zoom: 12,
      style: styleUrl(),
    })

    this.map.addControl(new maplibregl.NavigationControl({
      visualizePitch: true,
      visualizeRoll: true,
      showZoom: true,
      showCompass: true,
    }))
    this.map.addControl(this.#fitControl)

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
        paint: { "line-color": this.#accentColor, "line-width": 3 },
      })

      if (this.hasInitialWaypointsValue) {
        const seeded = this.initialWaypointsValue
        if (Array.isArray(seeded) && seeded.length !== 0) {
          this.#hydrateWaypoints(seeded)
        }
      }
    })

    this.map.on("click", (e) => this.#handleMapClick(e))

    this.#updateUI()
  }

  disconnect() {
    this.#waypointMarkers.forEach((m) => m.remove())
    this.#waypointMarkers = []
    this.#highlightMarker?.remove()
    this.#highlightMarker = null
    this.map?.remove()
    this.map = undefined
    if (this.#previewTimer) clearTimeout(this.#previewTimer)
  }

  // Public — used by elevation_profile_controller via outlet.
  showPoint(coordinate) {
    if (!this.map || !coordinate) return
    if (!this.#highlightMarker) {
      const el = document.createElement("div")
      el.style.width = "14px"
      el.style.height = "14px"
      el.style.borderRadius = "9999px"
      el.style.background = this.#accentColor
      el.style.border = "2px solid #ffffff"
      el.style.boxShadow = "0 0 0 1px rgba(0, 0, 0, 0.25)"
      el.style.pointerEvents = "none"
      this.#highlightMarker = new maplibregl.Marker({ element: el })
    }
    this.#highlightMarker.setLngLat(coordinate).addTo(this.map)
  }

  hidePoint() {
    this.#highlightMarker?.remove()
  }

  clear() {
    if (this.#waypoints.length === 0) return
    this.#setWaypoints([])
    this.#setRouteGeojson({ type: "FeatureCollection", features: [] })
    this.#fitControl.setBounds(null)
    this.#updateStats(null, null)
    this.elevationProfileOutlet?.clear?.()
  }

  undo() {
    if (this.#history.length === 0) return
    this.#redoStack.push(this.#waypoints.map((p) => [ p[0], p[1] ]))
    const previous = this.#history.pop()
    this.#setWaypoints(previous, { record: false })
  }

  redo() {
    if (this.#redoStack.length === 0) return
    this.#history.push(this.#waypoints.map((p) => [ p[0], p[1] ]))
    const next = this.#redoStack.pop()
    this.#setWaypoints(next, { record: false })
  }

  // Action entry points for `data-action` wiring — the private methods stay
  // internal; these expose them to the view.
  schedulePreview() {
    this.#schedulePreview()
  }

  retry() {
    this.#fetchPreview()
  }

  // --- waypoint mutation ---

  // Every mutation funnels through here. When `record` is true (the default)
  // we push the prior waypoints onto the history stack so `undo()` can return
  // to it — covering add, move, insert, remove, and clear with one path. Any
  // fresh user action also invalidates the redo stack (timeline diverged).
  #setWaypoints(next, { record = true } = {}) {
    const normalized = next.map((p) => [ p[0], p[1] ])
    if (record && !this.#isSameWaypoints(this.#waypoints, normalized)) {
      this.#history.push(this.#waypoints.map((p) => [ p[0], p[1] ]))
      if (this.#history.length > this.#historyLimit) this.#history.shift()
      this.#redoStack = []
    }

    this.#waypoints = normalized
    this.#waypointMarkers.forEach((m) => m.remove())
    this.#waypointMarkers = this.#waypoints.map((lngLat, i) => this.#buildWaypointMarker(lngLat, i))

    this.#updateUI()
    this.#schedulePreview()
  }

  #isSameWaypoints(a, b) {
    if (a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) {
      if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1]) return false
    }
    return true
  }

  #addWaypoint(lngLat) {
    this.#setWaypoints([ ...this.#waypoints, lngLat ])
  }

  #removeWaypointAt(idx) {
    const next = this.#waypoints.slice()
    next.splice(idx, 1)
    this.#setWaypoints(next)
  }

  #moveWaypoint(idx, lngLat) {
    const next = this.#waypoints.slice()
    next[idx] = lngLat
    this.#setWaypoints(next)
  }

  #insertWaypointAt(idx, lngLat) {
    const next = this.#waypoints.slice()
    next.splice(idx, 0, lngLat)
    this.#setWaypoints(next)
  }

  // Seeds the map from an external source and frames it. `record` decides
  // whether undo can walk back past this: false for the page's own baseline,
  // true for a GPX import, which overwrites whatever the user hand-placed.
  #hydrateWaypoints(seeded, { record = false } = {}) {
    this.#setWaypoints(seeded, { record })
    const bounds = seeded.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(seeded[0], seeded[0])
    )
    this.#fitControl.setBounds(bounds)
    this.map.fitBounds(bounds, { padding: 60, animate: false })
  }

  // --- marker construction ---

  #buildWaypointMarker(lngLat, index) {
    const el = document.createElement("div")
    el.style.width = "26px"
    el.style.height = "26px"
    el.style.borderRadius = "9999px"
    el.style.background = this.#accentColor
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
      this.#suppressMapClickUntil = Date.now() + 250
    })
    marker.on("dragend", () => {
      el.style.cursor = "grab"
      const i = this.#waypointMarkers.indexOf(marker)
      if (i === -1) return
      const ll = marker.getLngLat()
      this.#moveWaypoint(i, [ ll.lng, ll.lat ])
    })

    el.addEventListener("contextmenu", (e) => {
      e.preventDefault()
      const i = this.#waypointMarkers.indexOf(marker)
      if (i !== -1) this.#removeWaypointAt(i)
    })
    el.addEventListener("dblclick", (e) => {
      e.preventDefault()
      e.stopPropagation()
      const i = this.#waypointMarkers.indexOf(marker)
      if (i !== -1) this.#removeWaypointAt(i)
    })

    marker.addTo(this.map)
    return marker
  }

  // --- map click → add or insert ---

  #handleMapClick(e) {
    if (this.#suppressMapClickUntil && Date.now() < this.#suppressMapClickUntil) return

    const lngLat = [ e.lngLat.lng, e.lngLat.lat ]

    if (this.#waypoints.length >= 2 && this.#routeCoordinates.length >= 2 && this.#clickedOnRoute(e.point)) {
      const idx = this.#insertionIndexFor(lngLat)
      this.#insertWaypointAt(idx, lngLat)
      return
    }

    this.#addWaypoint(lngLat)
  }

  // A 3px line is too narrow for a pixel-perfect hit-test. Query a small bbox
  // around the click and include the wider casing layer.
  #clickedOnRoute(point) {
    const tolerance = 8
    const bbox = [
      [ point.x - tolerance, point.y - tolerance ],
      [ point.x + tolerance, point.y + tolerance ],
    ]
    const layers = [ "geojson-line", "geojson-line-casing" ].filter((id) => this.map.getLayer(id))
    if (layers.length === 0) return false
    return this.map.queryRenderedFeatures(bbox, { layers }).length > 0
  }

  // Map waypoints onto the routed polyline by nearest-index, then bracket the
  // click index between two waypoints — that's the insertion slot.
  #insertionIndexFor(clickLngLat) {
    const clickIdx = this.#nearestRouteIndex(clickLngLat)
    const waypointIndices = this.#waypoints.map((w) => this.#nearestRouteIndex(w))

    for (let i = 0; i < waypointIndices.length - 1; i++) {
      if (clickIdx >= waypointIndices[i] && clickIdx <= waypointIndices[i + 1]) {
        return i + 1
      }
    }
    return this.#waypoints.length
  }

  #nearestRouteIndex(lngLat) {
    let bestIdx = 0
    let bestDist = Infinity
    for (let i = 0; i < this.#routeCoordinates.length; i++) {
      const c = this.#routeCoordinates[i]
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

  #schedulePreview() {
    if (this.#previewTimer) clearTimeout(this.#previewTimer)
    this.#previewTimer = setTimeout(() => this.#fetchPreview(), PREVIEW_DEBOUNCE_MS)
  }

  async #fetchPreview() {
    if (this.#waypoints.length < 2) {
      this.#routeCoordinates = []
      this.#setRouteGeojson({ type: "FeatureCollection", features: [] })
      this.#updateStats(null, null)
      this.elevationProfileOutlet?.clear?.()
      return
    }

    const sport = this.hasSportSelectTarget ? this.sportSelectTarget.value : null
    if (!sport) return

    this.#setError(null)

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept":       "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.#csrfToken(),
        },
        body: JSON.stringify({ sport, waypoints: this.#waypoints }),
      })

      if (!response.ok) {
        const payload = await response.json().catch(() => ({}))
        this.#setError(payload.error || "routing_failed")
        return
      }

      const data = await response.json()
      this.#routeCoordinates = data.coordinates || data.geojson?.geometry?.coordinates || []
      this.#setRouteGeojson({ type: "FeatureCollection", features: [ data.geojson ] })
      this.#setFitBounds(data.geojson)
      this.#updateStats(data.distance_meters, data.elevation_gain_meters)
      this.#pushElevation(data.elevation_samples)
    } catch (err) {
      console.error(err)
      this.#setError("routing_failed")
    }
  }

  // --- GPX import ---

  // Seeds the planner from an uploaded track. The server only extracts and
  // downsamples waypoints; routing happens on the preview that #setWaypoints
  // schedules, so this path stays cheap and undo/redo behave as usual.
  async importGpx() {
    const file = this.#gpxFile()
    if (!file) return

    if (!/\.gpx$/i.test(file.name)) return this.#failImport("gpx_invalid_type")
    if (file.size > MAX_GPX_BYTES) return this.#failImport("gpx_too_large")

    this.#setError(null)
    this.#setImporting(true)

    try {
      const body = new FormData()
      body.append("gpx_source", file)

      const response = await fetch(this.importUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.#csrfToken() },
        body,
      })

      const payload = await response.json().catch(() => ({}))
      if (!response.ok) return this.#failImport(payload.error || "gpx_unreadable")

      const waypoints = Array.isArray(payload.waypoints) ? payload.waypoints : []
      if (waypoints.length < 2) return this.#failImport("gpx_no_points")

      this.#clearGpxFile()
      // record: true — an import replaces hand-placed waypoints, so undo has to
      // be able to bring them back.
      this.#hydrateWaypoints(waypoints, { record: true })
      this.#applyImportedName(payload.name)
    } catch (err) {
      console.error(err)
      this.#failImport("gpx_unreadable")
    } finally {
      this.#setImporting(false)
    }
  }

  #failImport(code) {
    this.#clearGpxFile()
    this.#setError(code)
  }

  // Null-guarded: `change` also fires when the picker is cancelled or cleared.
  #gpxFile() {
    if (!this.hasGpxInputTarget) return null
    return this.gpxInputTarget.files?.[0] ?? null
  }

  #clearGpxFile() {
    if (this.hasGpxInputTarget) this.gpxInputTarget.value = ""
  }

  #setImporting(flag) {
    if (this.hasGpxInputTarget) this.gpxInputTarget.disabled = flag
    if (this.hasGpxBusyTarget) this.gpxBusyTarget.classList.toggle("hidden", !flag)
    this.element.setAttribute("aria-busy", flag ? "true" : "false")
  }

  #applyImportedName(name) {
    if (!name || !this.hasNameFieldTarget) return
    if (this.nameFieldTarget.value.trim() !== "") return
    this.nameFieldTarget.value = name
  }

  #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  #pushElevation(samples) {
    if (!this.hasElevationProfileOutlet) return
    if (!Array.isArray(samples) || samples.length === 0) {
      this.elevationProfileOutlet.clear?.()
      return
    }
    const labels = samples.map((s) => s[0])
    const data   = samples.map((s) => s[1])
    this.elevationProfileOutlet.updateData?.({ labels, data }, this.#routeCoordinates)
  }

  #setRouteGeojson(geojson) {
    const source = this.map?.getSource("route")
    if (source) source.setData(geojson)
  }

  #setFitBounds(feature) {
    const coords = feature?.geometry?.coordinates
    if (!coords?.length) return
    const bounds = coords.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(coords[0], coords[0])
    )
    this.#fitControl.setBounds(bounds)
  }

  #updateStats(distanceMeters, elevationGainMeters) {
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

  #setError(code) {
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
    // "Réessayer" re-runs the preview, which does nothing for a rejected GPX —
    // the file input has already been cleared.
    if (this.hasRetryTarget) this.retryTarget.classList.toggle("hidden", code.startsWith("gpx_"))
    this.errorTarget.classList.remove("hidden")
  }

  #updateUI() {
    if (this.hasWaypointsFieldTarget) {
      this.waypointsFieldTarget.value = JSON.stringify(this.#waypoints)
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = this.#waypoints.length < 2
    }
    if (this.hasHintTarget) {
      this.hintTarget.classList.toggle("hidden", this.#waypoints.length > 0)
    }
    if (this.hasClearTarget) {
      this.clearTarget.disabled = this.#waypoints.length === 0
    }
    if (this.hasUndoTarget) {
      this.undoTarget.disabled = this.#history.length === 0
    }
    if (this.hasRedoTarget) {
      this.redoTarget.disabled = this.#redoStack.length === 0
    }
  }

  #initialCenter() {
    if (this.hasInitialWaypointsValue && this.initialWaypointsValue.length > 0) {
      return this.initialWaypointsValue[0]
    }
    return [ this.initialLngValue, this.initialLatValue ]
  }
}
