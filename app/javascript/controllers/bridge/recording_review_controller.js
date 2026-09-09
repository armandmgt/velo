import { BridgeComponent } from "@hotwired/hotwire-native-bridge"
import * as maplibregl from "maplibre-gl"
import { primaryAccentColor, styleUrl } from "controllers/lib/map_helpers"
import { encodeGpx } from "controllers/lib/gpx_encoder"
import { lapSplits, splitAverageSpeed } from "controllers/lib/lap_splits"
import {
  distanceKilometers,
  elapsedString,
  pace,
  speedKmh,
  usesPace,
} from "controllers/lib/recording_formatters"

// Connects to data-controller="bridge--recording-review"
export default class extends BridgeComponent {
  static component = "recording-review"
  static targets = [
    "review",
    "file",
    "fileField",
    "discard",
    "uuid",
    "sport",
    "submit",
    "map",
    "distance",
    "elapsed",
    "moving",
    "average",
    "averageCaption",
    "lapCount",
    "lapSummary",
    "splits",
    "splitRowTemplate",
    "status",
  ]

  connect() {
    super.connect()
    // The page ships as the plain upload form, so a shell without this
    // component still works.
    this.#enterLoadingState()
    this.send("connect", {}, (message) => this.#receive(message.data))
  }

  disconnect() {
    super.disconnect()
    this.map?.remove()
    this.map = undefined
  }

  submitEnd(event) {
    if (!event.detail?.success) return
    this.send("committed", { url: event.detail.fetchResponse?.response?.url })
  }

  discard(event) {
    event.preventDefault()
    this.send("discard")
  }

  async #receive(data) {
    if (!data?.handoff) return this.#fallBackToUpload()

    try {
      const handoff = await this.#decode(data.handoff)
      // MapLibre measures its container at construction, so reveal first.
      this.#showReview()
      this.#render(handoff)
      this.#attachGpx(handoff)
    } catch (error) {
      this.#fail(error)
    }
  }

  // deflate-raw, not gzip: it is what both shells' compressors already emit.
  async #decode(base64) {
    const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw"))
    return JSON.parse(await new Response(stream).text())
  }

  #render(handoff) {
    const stats = handoff.stats ?? {}
    const paced = usesPace(handoff.sport)

    this.uuidTarget.value = handoff.recordingUuid ?? ""
    if (handoff.sport) this.sportTarget.value = handoff.sport

    this.distanceTarget.textContent = distanceKilometers(stats.distance ?? 0)
    this.elapsedTarget.textContent = elapsedString(stats.elapsed ?? 0)
    this.movingTarget.textContent = elapsedString(stats.movingTime ?? 0)
    this.averageTarget.textContent = paced
      ? pace(stats.averageSpeed ?? 0)
      : speedKmh(stats.averageSpeed ?? 0)
    this.averageCaptionTarget.textContent = paced ? "Allure" : "Moy. km/h"

    this.#renderSplits(handoff, stats)
    this.#renderRoute(handoff)
  }

  #renderSplits(handoff, stats) {
    const splits = lapSplits({
      boundaries: handoff.laps ?? [],
      totalDistance: stats.distance ?? 0,
      totalElapsed: stats.elapsed ?? 0,
    })
    const paced = usesPace(handoff.sport)

    this.lapCountTarget.textContent = String(splits.length)
    this.lapSummaryTarget.textContent = splits.length === 1 ? "1 tour" : `${splits.length} tours`

    this.splitsTarget.replaceChildren(
      ...splits.map((split) => {
        const row = this.splitRowTemplateTarget.content.cloneNode(true)
        const speed = splitAverageSpeed(split)
        row.querySelector("[data-split-ordinal]").textContent = String(split.ordinal)
        row.querySelector("[data-split-distance]").textContent = `${distanceKilometers(split.distance)} km`
        row.querySelector("[data-split-elapsed]").textContent = elapsedString(split.elapsed)
        row.querySelector("[data-split-speed]").textContent = paced
          ? pace(speed)
          : `${speedKmh(speed)} km/h`
        return row
      })
    )
  }

  #renderRoute(handoff) {
    const coordinates = (handoff.points ?? []).map((point) => [point.lon, point.lat])
    if (coordinates.length === 0) return

    const accent = primaryAccentColor()
    const bounds = coordinates.reduce(
      (box, coordinate) => box.extend(coordinate),
      new maplibregl.LngLatBounds(coordinates[0], coordinates[0])
    )

    this.map = new maplibregl.Map({
      container: this.mapTarget,
      style: styleUrl(),
      bounds,
      // Near-zero bounds would otherwise fit past the deepest tile.
      fitBoundsOptions: { padding: 32, maxZoom: 16 },
      interactive: false,
      // The summary card covers the bottom-right, and the tile licence
      // requires the attribution stay legible.
      attributionControl: false,
    })

    this.map.addControl(new maplibregl.AttributionControl({ compact: true }), "top-right")

    this.map.on("load", () => {
      this.map.addSource("route", {
        type: "geojson",
        data: {
          type: "Feature",
          properties: {},
          geometry: { type: "LineString", coordinates },
        },
      })
      this.map.addLayer({
        id: "route-casing",
        type: "line",
        source: "route",
        paint: { "line-color": "#ffffff", "line-width": 5, "line-opacity": 0.9 },
      })
      this.map.addLayer({
        id: "route-line",
        type: "line",
        source: "route",
        paint: { "line-color": accent, "line-width": 3 },
      })
    })

    this.#addEndpointMarker(coordinates.at(0), accent)
    this.#addEndpointMarker(coordinates.at(-1), "#111111")
  }

  #addEndpointMarker(coordinate, color) {
    const element = document.createElement("div")
    element.style.cssText = `width:12px;height:12px;border-radius:9999px;background:${color};border:2px solid #ffffff;box-shadow:0 0 0 1px rgba(0,0,0,0.25)`
    new maplibregl.Marker({ element }).setLngLat(coordinate).addTo(this.map)
  }

  #attachGpx(handoff) {
    const gpx = encodeGpx(handoff, document.documentElement.dataset.bridgePlatform)
    const transfer = new DataTransfer()
    // The filename, not the field name, routes this to GpxExtractor.
    transfer.items.add(new File([gpx], "recording.gpx", { type: "application/gpx+xml" }))
    this.fileTarget.files = transfer.files
  }

  #enterLoadingState() {
    this.statusTarget.hidden = false
    this.submitTarget.disabled = true
  }

  #fallBackToUpload() {
    this.statusTarget.hidden = true
    this.submitTarget.disabled = false
  }

  #showReview() {
    this.reviewTarget.hidden = false
    this.discardTarget.hidden = false
    this.fileFieldTarget.classList.add("hidden")
    this.statusTarget.hidden = true
    this.submitTarget.disabled = false
  }

  #fail(error) {
    this.statusTarget.hidden = false
    this.statusTarget.textContent =
      "L'enregistrement n'a pas pu être chargé. Il est conservé sur l'appareil."
    this.submitTarget.disabled = true
    console.error("[recording-review] handoff failed", error)
  }
}
