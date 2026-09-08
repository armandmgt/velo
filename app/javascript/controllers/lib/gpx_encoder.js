// Serializes a handed-off recording to GPX 1.1 for upload (#116, ADR 0003).
//
// This is the *only* GPX encoder in the project. It used to exist twice, as
// `RecordingGPXEncoder.swift` and `RecordingGpxEncoder.kt`; since the review
// screen became a web page the shells hand over structured points and this
// builds the file the form uploads.
//
// Emits exactly the schema locked in the S0 contract
// (`docs/native-recording/s0-gpx-upload-contract.md` §2), proven to round-trip
// by the server fixture `test/fixtures/files/gpx/native_recording.gpx`. The
// device sends **positions + time + sensors only** — distance, speed, elevation
// gain and the PostGIS path are all derived server-side by `GpxExtractor`, so we
// deliberately do NOT emit `<speed>` or any summary.

// Default track name when the user didn't name the activity; a fallback the
// server's `activity[name]` param (and the awaiting-name prompt) override.
export const DEFAULT_TRACK_NAME = "Sortie enregistrée sur le téléphone"

// Best-effort `<trk><type>`, emitted for GPX self-containedness only — the
// `activity[sport]` param wins server-side. `workout` has no mapping and must
// travel via the param alone (S0 §3).
const GPX_TYPES = {
  bike: "cycling",
  mountain_bike_ride: "mountainbiking",
  gravel_ride: "gravelbiking",
  virtual_ride: "virtualride",
  e_bike_ride: "ebiking",
  run: "running",
  trail_run: "trailrunning",
  virtual_run: "virtualrunning",
  walk: "walking",
  hike: "hiking",
  alpine_ski: "alpineski",
  nordic_ski: "nordicski",
  swim: "swimming",
}

const CREATORS = { ios: "Velo iOS", android: "Velo Android" }

// UTC ISO-8601 with a `Z` suffix and no fractional seconds, e.g.
// `2026-06-25T08:00:00Z` (S0 §2) — matching Swift's `.withInternetDateTime`.
function iso8601(value) {
  return new Date(value).toISOString().replace(/\.\d+Z$/, "Z")
}

function xmlEscape(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;")
}

function trackPointExtension(point) {
  if (point.hr === undefined && point.cad === undefined) return []

  const lines = ["     <gpxtpx:TrackPointExtension>"]
  if (point.hr !== undefined) lines.push(`      <gpxtpx:hr>${point.hr}</gpxtpx:hr>`)
  if (point.cad !== undefined) lines.push(`      <gpxtpx:cad>${point.cad}</gpxtpx:cad>`)
  lines.push("     </gpxtpx:TrackPointExtension>")
  return lines
}

function trackpoint(point) {
  // Decimal degrees with 7 dp (≈11 mm), matching the reference fixture.
  const lines = [`   <trkpt lat="${point.lat.toFixed(7)}" lon="${point.lon.toFixed(7)}">`]
  if (point.ele !== undefined) lines.push(`    <ele>${point.ele.toFixed(1)}</ele>`)
  lines.push(`    <time>${iso8601(point.t)}</time>`)

  const tpx = trackPointExtension(point)
  if (tpx.length > 0 || point.pw !== undefined) {
    lines.push("    <extensions>")
    lines.push(...tpx)
    // Strava-style <power>, sibling of TrackPointExtension (S0 §2).
    if (point.pw !== undefined) lines.push(`     <power>${point.pw}</power>`)
    lines.push("    </extensions>")
  }

  lines.push("   </trkpt>")
  return lines
}

// `handoff` is the decoded payload: `{ sport, startedAt, points: [...] }`.
// `platform` is the bridge platform ("ios" / "android"), used only for the
// cosmetic `creator` attribute.
export function encodeGpx(handoff, platform) {
  const points = handoff.points ?? []
  const creator = CREATORS[platform] ?? "Velo"

  const lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<gpx creator="${xmlEscape(creator)}" version="1.1"`,
    '     xmlns="http://www.topografix.com/GPX/1/1"',
    '     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">',
    " <metadata>",
    `  <time>${iso8601(points[0]?.t ?? handoff.startedAt)}</time>`,
    " </metadata>",
    " <trk>",
    `  <name>${xmlEscape(DEFAULT_TRACK_NAME)}</name>`,
  ]

  const type = GPX_TYPES[handoff.sport]
  if (type) lines.push(`  <type>${type}</type>`)

  lines.push("  <trkseg>")
  for (const point of points) lines.push(...trackpoint(point))
  lines.push("  </trkseg>", " </trk>", "</gpx>", "")

  return lines.join("\n")
}
