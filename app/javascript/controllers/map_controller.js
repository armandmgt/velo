import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"

class BackToCenterControl {
  constructor(center) {
    this._center = center
  }

  onAdd(map) {
    this._map = map

    const span = document.createElement("span")
    span.className = "maplibregl-ctrl-icon"

    const button = document.createElement("button")
    button.className = "maplibregl-ctrl-geolocate"
    button.ariaLabel = "Back to center"
    button.addEventListener("click", () => {
      this._map.flyTo({ center: this._center, zoom: 13 })
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
    zoom: Number,
  }

  connect() {
    this.map = new maplibregl.Map({
      container: this.element,
      center: [this.lngValue, this.latValue],
      zoom: this.zoomValue || 13,
      style: "/map_style",
    })

    this.map.addControl(new maplibregl.NavigationControl({
      visualizePitch: true,
      visualizeRoll: true,
      showZoom: true,
      showCompass: true,
    }))
    this.map.addControl(new BackToCenterControl([this.lngValue, this.latValue]))
  }
}
