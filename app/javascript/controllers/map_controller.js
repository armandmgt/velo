import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    zoom: Number
  }

  connect() {
    this.center = {
      lat: this.latValue,
      lng: this.lngValue
    }

    this.zoom = this.zoomValue || 13

    this.isDragging = false
    this.lastMouse = { x: 0, y: 0 }

    this.markers = [
      { lat: 48.8566, lng: 2.3522 },
      { lat: 48.86, lng: 2.34 }
    ]

    this.bindEvents()
    this.render()
  }

  // --- Projection
  project(lat, lng) {
    const tileSize = 256
    const scale = tileSize * Math.pow(2, this.zoom)

    const x = (lng + 180) / 360 * scale

    const latRad = lat * Math.PI / 180
    const y = (
      (1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI)
      / 2
    ) * scale

    return { x, y }
  }

  unproject(x, y) {
    const tileSize = 256
    const scale = tileSize * Math.pow(2, this.zoom)

    const lng = (x / scale) * 360 - 180

    const n = Math.PI - (2 * Math.PI * y) / scale
    const lat = (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))

    return { lat, lng }
  }

  // --- Render
  render() {
    this.element.innerHTML = ""

    const rect = this.element.getBoundingClientRect()
    const width = rect.width
    const height = rect.height

    const centerPx = this.project(this.center.lat, this.center.lng)

    const startX = Math.floor((centerPx.x - width / 2) / 256)
    const startY = Math.floor((centerPx.y - height / 2) / 256)

    const endX = Math.floor((centerPx.x + width / 2) / 256)
    const endY = Math.floor((centerPx.y + height / 2) / 256)

    for (let x = startX; x <= endX; x++) {
      for (let y = startY; y <= endY; y++) {
        const img = document.createElement("img")

        img.src = `https://tile.openstreetmap.org/${this.zoom}/${x}/${y}.png`

        img.style.left = `${x * 256 - centerPx.x + width / 2}px`
        img.style.top  = `${y * 256 - centerPx.y + height / 2}px`

        this.element.appendChild(img)
      }
    }

    this.renderMarkers(centerPx, width, height)
  }

  renderMarkers(centerPx, width, height) {
    this.markers.forEach(m => {
      const p = this.project(m.lat, m.lng)

      const el = document.createElement("div")
      el.className = "marker"

      el.style.left = `${p.x - centerPx.x + width / 2}px`
      el.style.top  = `${p.y - centerPx.y + height / 2}px`

      this.element.appendChild(el)
    })
  }

  // --- Events
  bindEvents() {
    this.element.addEventListener("mousedown", this.startDrag.bind(this))
    window.addEventListener("mouseup", this.stopDrag.bind(this))
    window.addEventListener("mousemove", this.drag.bind(this))
    this.element.addEventListener("wheel", this.zoomMap.bind(this), { passive: false })
  }

  startDrag(e) {
    this.isDragging = true
    this.lastMouse = { x: e.clientX, y: e.clientY }
    this.element.style.cursor = "grabbing"
  }

  stopDrag() {
    this.isDragging = false
    this.element.style.cursor = "grab"
  }

  drag(e) {
    if (!this.isDragging) return

    const dx = e.clientX - this.lastMouse.x
    const dy = e.clientY - this.lastMouse.y

    this.lastMouse = { x: e.clientX, y: e.clientY }

    const centerPx = this.project(this.center.lat, this.center.lng)

    const newCenterPx = {
      x: centerPx.x - dx,
      y: centerPx.y - dy
    }

    this.center = this.unproject(newCenterPx.x, newCenterPx.y)

    this.render()
  }

  zoomMap(e) {
    e.preventDefault()

    this.zoom += e.deltaY < 0 ? 1 : -1
    this.zoom = Math.max(2, Math.min(19, this.zoom))

    this.render()
  }
}