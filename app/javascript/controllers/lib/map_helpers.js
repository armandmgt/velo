// MapLibre's style parser only understands legacy CSS color syntax
// (rgb/rgba/hex/named), not modern formats like oklch() that Tailwind v4
// emits. Reading ctx.fillStyle back isn't reliable: in current Chromium
// it just returns the oklch string unchanged. Instead, paint a 1×1 pixel
// and read the rendered RGB — that's always normalized.
export function resolveCssColor(color) {
  if (!color) return null

  const canvas = document.createElement("canvas")
  canvas.width = 1
  canvas.height = 1
  const ctx = canvas.getContext("2d")
  if (!ctx) return null

  try {
    ctx.fillStyle = color
    ctx.fillRect(0, 0, 1, 1)
    const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data
    return `rgba(${r}, ${g}, ${b}, ${a / 255})`
  } catch {
    return null
  }
}

export function primaryAccentColor(fallback = "#ff0000") {
  const raw = getComputedStyle(document.documentElement)
    .getPropertyValue("--color-primary")
    .trim()
  return resolveCssColor(raw) || fallback
}

export class FitToBoundsControl {
  #bounds
  #map
  #container

  constructor(bounds) {
    this.#bounds = bounds
  }

  setBounds(bounds) {
    this.#bounds = bounds
  }

  onAdd(map) {
    this.#map = map

    const span = document.createElement("span")
    span.className = "maplibregl-ctrl-icon"

    const button = document.createElement("button")
    button.className = "maplibregl-ctrl-geolocate"
    button.ariaLabel = "Back to center"
    button.addEventListener("click", () => {
      if (this.#bounds) this.#map.fitBounds(this.#bounds, { padding: 40 })
    })
    button.appendChild(span)

    this.#container = document.createElement("div")
    this.#container.className = "maplibregl-ctrl maplibregl-ctrl-group"
    this.#container.appendChild(button)

    return this.#container
  }

  onRemove() {
    this.#container.remove()
    this.#map = undefined
  }
}

export function styleUrl() {
  return "https://api.maptiler.com/maps/streets/style.json?key=" + (window.MAPTILER_API_KEY || "")
}
