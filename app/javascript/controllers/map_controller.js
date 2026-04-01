import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl";

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    zoom: Number
  }

  connect() {
    this.map = new maplibregl.Map({
      container: this.element,
      center: [this.lngValue, this.latValue], // starting position [lng, lat]
      zoom: this.zoomValue || 13, // starting zoom
      style: '/map_style',
    });
  }
}
