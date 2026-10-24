import { Controller } from "@hotwired/stimulus"

const EARTH_RADIUS_M = 6_371_000

function haversine([ lng1, lat1 ], [ lng2, lat2 ]) {
  const rad = Math.PI / 180
  const a = Math.sin((lat2 - lat1) * rad / 2) ** 2 +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin((lng2 - lng1) * rad / 2) ** 2
  return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// Picks a segment's start and end among the activity's path vertices, with the
// two sliders or by clicking the map, and draws the chosen stretch.
export default class extends Controller {
  static targets = [ "start", "end", "distance", "submit" ]
  static values = { coordinates: Array, minDistance: Number }
  static outlets = [ "map" ]

  #along = []

  connect() {
    this.#along = this.coordinatesValue.reduce((acc, point, i, all) => {
      acc.push(i === 0 ? 0 : acc[i - 1] + haversine(all[i - 1], point))
      return acc
    }, [])
    this.update()
  }

  mapOutletConnected() {
    this.update()
  }

  update(event) {
    let start = Number(this.startTarget.value)
    let end = Number(this.endTarget.value)
    if (start >= end) {
      if (event?.target === this.endTarget) end = Math.min(start + 1, this.#along.length - 1)
      else start = Math.max(end - 1, 0)
      this.startTarget.value = start
      this.endTarget.value = end
    }

    const meters = (this.#along[end] ?? 0) - (this.#along[start] ?? 0)
    this.distanceTarget.textContent = meters < 1000
      ? `${Math.round(meters)} m`
      : `${(meters / 1000).toLocaleString("fr-FR", { maximumFractionDigits: 2 })} km`
    this.submitTarget.disabled = meters < this.minDistanceValue
    if (this.hasMapOutlet) this.mapOutlet.highlightStretch(start, end, { fit: false })
  }

  // A map click moves whichever end of the stretch is nearer along the track.
  pick({ detail: { lngLat } }) {
    let nearest = 0
    this.coordinatesValue.forEach((point, i) => {
      if (haversine(point, lngLat) < haversine(this.coordinatesValue[nearest], lngLat)) nearest = i
    })
    const start = Number(this.startTarget.value)
    const end = Number(this.endTarget.value)
    const handle = Math.abs(nearest - start) <= Math.abs(nearest - end) ? this.startTarget : this.endTarget
    handle.value = nearest
    this.update({ target: handle })
  }
}
