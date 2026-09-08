import { BridgeComponent } from "@hotwired/hotwire-native-bridge"
import maplibregl from "maplibre-gl"
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
//
// Turns `/activities/new` into the recording review screen the shells used to
// build natively (#116, ADR 0003 — supersedes #66/#67).
//
// On connect it asks the shell for the **handoff** — the finished recording's
// points, lap boundaries, stats and sport, gzipped and base64'd into one bridge
// message. From that single payload it draws the route, renders the splits and
// the three stats, encodes the GPX, and puts it into the form's real
// `activity[fit_file]` input via `DataTransfer`. The form then submits like any
// other Turbo form: CSRF from the page's meta tag, `422` re-rendering with
// `activity.errors`, `201` redirecting to the new activity.
//
// #66 claimed a webview could not do this. What a webview cannot do is set a
// file input's *path*; attaching a JS-constructed `File` has worked since Safari
// 14.1, and the iOS deployment target is 17.0.
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
    // The page's default state is the plain upload form: file picker visible, no
    // review chrome, submit live. That way a shell *without* this component — an
    // older app against a newer server — still gets a form that works, rather
    // than a review screen nothing can ever fill. Only once we know a handoff is
    // on its way do we take the form over.
    this.#enterLoadingState()
    this.send("connect", {}, (message) => this.#receive(message.data))
  }

  disconnect() {
    super.disconnect()
    this.map?.remove()
    this.map = undefined
  }

  /**
   * Enregistrer succeeded — only now may the shell clear the local recording,
   * and the URL it landed on is the activity the shell should show. The
   * `recording_uuid` submitted with the form makes a replay resolve to this same
   * activity, so a shell killed before this message arrives cannot duplicate it.
   */
  submitEnd(event) {
    if (!event.detail?.success) return
    this.send("committed", { url: event.detail.fetchResponse?.response?.url })
  }

  /** Supprimer — the shell owns the confirmation and the delete. */
  discard(event) {
    event.preventDefault()
    this.send("discard")
  }

  // MARK: - Handoff

  async #receive(data) {
    // No pending recording. The tab bar's "+" routes here too — same URL, and
    // the shell has nothing to hand over — so this is the plain upload form.
    // Reveal the file picker rather than stranding the rider on a review screen
    // for a ride that doesn't exist.
    if (!data?.handoff) return this.#fallBackToUpload()

    try {
      const handoff = await this.#decode(data.handoff)
      // Reveal before drawing: MapLibre measures its container at construction,
      // and a hidden one measures zero.
      this.#showReview()
      this.#render(handoff)
      this.#attachGpx(handoff)
    } catch (error) {
      this.#fail(error)
    }
  }

  // Raw DEFLATE + base64: a six-hour ride at ~1 Hz is ~21,600 points, and the
  // bridge's native→web leg inlines its JSON into an `evaluateJavaScript` source
  // string — raw, that is megabytes. 1 Hz GPS text compresses roughly ten to
  // one, which keeps even the worst realistic ride in the low hundreds of KB, so
  // one message suffices and there is no chunk-reassembly to get wrong.
  //
  // "deflate-raw" rather than gzip because it is what both shells' compressors
  // emit natively (iOS `COMPRESSION_ZLIB`, Android `Deflater(nowrap: true)`) —
  // no gzip container or CRC32 hand-rolled twice.
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

  // The points already crossed the bridge at full fidelity for the GPX, so the
  // trace is drawn from them directly — there is nothing to save by simplifying
  // something already paid for, and MapLibre draws the line on the GPU.
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
      fitBoundsOptions: { padding: 32 },
      // A still rendering of the ride just recorded — nothing to pan to.
      interactive: false,
      attributionControl: { compact: true },
    })

    this.map.on("load", () => {
      this.map.addSource("route", {
        type: "geojson",
        data: {
          type: "Feature",
          properties: {},
          geometry: { type: "LineString", coordinates },
        },
      })
      // Casing under the line, same as the activity map.
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

  // The moment #66 said was impossible: a `File` built in JS, attached to the
  // form's real file input. The part's filename MUST end in `.gpx` — the server
  // dispatches to `GpxExtractor` on the filename, not the field name (S0 §4).
  #attachGpx(handoff) {
    const gpx = encodeGpx(handoff, document.documentElement.dataset.bridgePlatform)
    const transfer = new DataTransfer()
    transfer.items.add(new File([gpx], "recording.gpx", { type: "application/gpx+xml" }))
    this.fileTarget.files = transfer.files
  }

  #enterLoadingState() {
    this.statusTarget.hidden = false
    this.submitTarget.disabled = true
  }

  /**
   * No pending recording (or none we could read). Leave the page exactly as the
   * server rendered it — the plain upload form — and hand the submit back.
   */
  #fallBackToUpload() {
    this.statusTarget.hidden = true
    this.submitTarget.disabled = false
  }

  /** Swap the upload form for the review: chrome in, file picker out. */
  #showReview() {
    this.reviewTarget.hidden = false
    this.discardTarget.hidden = false
    this.fileFieldTarget.classList.add("hidden")
    this.statusTarget.hidden = true
    this.submitTarget.disabled = false
  }

  /**
   * A handoff arrived but could not be read. Don't offer the upload form as a
   * consolation — the rider has no file to pick, and the recording is still on
   * the device. Say so, and leave the submit disabled.
   */
  #fail(error) {
    this.statusTarget.hidden = false
    this.statusTarget.textContent =
      "L'enregistrement n'a pas pu être chargé. Il est conservé sur l'appareil."
    this.submitTarget.disabled = true
    console.error("[recording-review] handoff failed", error)
  }
}
