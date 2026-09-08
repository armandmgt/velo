// Shared formatting for a handed-off recording's stats (#116, ADR 0003).
//
// Mirrors the shells' `RecordingFormatters`, which still format the *live*
// dashboard while riding — the numbers a rider reads on the review screen must
// not shift the moment the screen becomes a web page.

/** `x.xx` km from a distance in metres. */
export function distanceKilometers(meters) {
  return (meters / 1000).toFixed(2)
}

/** `H:MM:SS` once past an hour, else `MM:SS`. */
export function elapsedString(seconds) {
  const total = Math.max(Math.round(seconds || 0), 0)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secs = total % 60
  const pad = (n) => String(n).padStart(2, "0")
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${pad(minutes)}:${pad(secs)}`
}

/**
 * `m:ss/km`. Near-zero speed reads as `—` rather than an absurd figure —
 * the same guard the shells apply.
 */
export function pace(metersPerSecond) {
  if (!(metersPerSecond > 0.3)) return "—"
  const secondsPerKm = 1000 / metersPerSecond
  const minutes = Math.floor(secondsPerKm / 60)
  const seconds = Math.round(secondsPerKm) % 60
  return `${minutes}:${String(seconds).padStart(2, "0")}/km`
}

/** km/h, bare — the unit lives in the caption beside it. */
export function speedKmh(metersPerSecond) {
  return (Math.max(metersPerSecond, 0) * 3.6).toFixed(1)
}

/** Running-style sports read as pace (min/km); everything else as speed (km/h). */
const PACE_SPORTS = new Set(["run", "trail_run", "virtual_run", "walk"])

export function usesPace(sport) {
  return PACE_SPORTS.has(sport)
}
