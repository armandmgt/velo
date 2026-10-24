import { Controller } from "@hotwired/stimulus"
import * as maplibregl from "maplibre-gl"
import { primaryAccentColor, styleUrl } from "controllers/lib/map_helpers"

const PARIS = [2.3522, 48.8566]
const CIRCLE_STEPS = 64
const EARTH_RADIUS_M = 6371000

export default class extends Controller {
  static targets = ["map", "latitude", "longitude", "radius"]

  #map
  #marker
  #accentColor

  connect() {
    this.#accentColor = primaryAccentColor()
    const center = this.#center()

    this.#map = new maplibregl.Map({
      container: this.mapTarget,
      center: center || PARIS,
      zoom: center ? 14 : 11,
      style: styleUrl(),
    })
    this.#map.addControl(new maplibregl.NavigationControl({ showCompass: false }))
    this.#map.on("click", (event) => this.#place([event.lngLat.lng, event.lngLat.lat]))
    this.#map.on("load", () => {
      this.#map.addSource("zone", { type: "geojson", data: this.#circle() })
      this.#map.addLayer({
        id: "zone-fill",
        type: "fill",
        source: "zone",
        paint: { "fill-color": this.#accentColor, "fill-opacity": 0.2 },
      })
      this.#map.addLayer({
        id: "zone-outline",
        type: "line",
        source: "zone",
        paint: { "line-color": this.#accentColor, "line-width": 2 },
      })
      if (center) this.#showMarker(center)
    })
  }

  disconnect() {
    this.#marker?.remove()
    this.#map?.remove()
    this.#map = undefined
    this.#marker = undefined
  }

  redraw() {
    this.#map?.getSource("zone")?.setData(this.#circle())
  }

  #place(lngLat) {
    this.longitudeTarget.value = lngLat[0]
    this.latitudeTarget.value = lngLat[1]
    this.#showMarker(lngLat)
    this.redraw()
  }

  #showMarker(lngLat) {
    this.#marker ??= new maplibregl.Marker({ color: this.#accentColor })
    this.#marker.setLngLat(lngLat).addTo(this.#map)
  }

  #center() {
    const lng = parseFloat(this.longitudeTarget.value)
    const lat = parseFloat(this.latitudeTarget.value)
    return Number.isFinite(lng) && Number.isFinite(lat) ? [lng, lat] : null
  }

  // Approximates the zone's circle on the ground; the server decides what is
  // hidden, this is only a preview.
  #circle() {
    const center = this.#center()
    if (!center) return { type: "FeatureCollection", features: [] }

    const radius = parseFloat(this.radiusTarget.value)
    const [lng, lat] = center.map((degrees) => degrees * Math.PI / 180)
    const angular = radius / EARTH_RADIUS_M
    const ring = Array.from({ length: CIRCLE_STEPS + 1 }, (_, step) => {
      const bearing = (step / CIRCLE_STEPS) * 2 * Math.PI
      const pointLat = Math.asin(Math.sin(lat) * Math.cos(angular) +
        Math.cos(lat) * Math.sin(angular) * Math.cos(bearing))
      const pointLng = lng + Math.atan2(Math.sin(bearing) * Math.sin(angular) * Math.cos(lat),
        Math.cos(angular) - Math.sin(lat) * Math.sin(pointLat))
      return [pointLng * 180 / Math.PI, pointLat * 180 / Math.PI]
    })

    return { type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [ring] } }
  }
}
