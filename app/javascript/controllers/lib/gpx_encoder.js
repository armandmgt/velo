// Pinned to test/fixtures/files/gpx/native_recording.gpx. Positions, time and
// sensors only — GpxExtractor derives the rest, so a <speed> or summary emitted
// here would be ignored.

export const DEFAULT_TRACK_NAME = "Sortie enregistrée sur le téléphone"

// activity[sport] wins server-side. `workout` is absent because it has no GPX
// mapping and must travel via that param alone.
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
  const lines = [`   <trkpt lat="${point.lat.toFixed(7)}" lon="${point.lon.toFixed(7)}">`]
  if (point.ele !== undefined) lines.push(`    <ele>${point.ele.toFixed(1)}</ele>`)
  lines.push(`    <time>${iso8601(point.t)}</time>`)

  const tpx = trackPointExtension(point)
  if (tpx.length > 0 || point.pw !== undefined) {
    lines.push("    <extensions>")
    lines.push(...tpx)
    if (point.pw !== undefined) lines.push(`     <power>${point.pw}</power>`)
    lines.push("    </extensions>")
  }

  lines.push("   </trkpt>")
  return lines
}

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
