// Mirrors the shells' RecordingFormatters: the numbers a rider watched while
// riding must not shift once the screen is a web page.

export function distanceKilometers(meters) {
  return (meters / 1000).toFixed(2)
}

export function elapsedString(seconds) {
  const total = Math.max(Math.round(seconds || 0), 0)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secs = total % 60
  const pad = (n) => String(n).padStart(2, "0")
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${pad(minutes)}:${pad(secs)}`
}

/** Near-zero speed reads as `—` rather than an absurd figure. */
export function pace(metersPerSecond) {
  if (!(metersPerSecond > 0.3)) return "—"
  const secondsPerKm = 1000 / metersPerSecond
  const minutes = Math.floor(secondsPerKm / 60)
  const seconds = Math.round(secondsPerKm) % 60
  return `${minutes}:${String(seconds).padStart(2, "0")}/km`
}

/** Bare number — the unit lives in the caption beside it. */
export function speedKmh(metersPerSecond) {
  return (Math.max(metersPerSecond, 0) * 3.6).toFixed(1)
}

const PACE_SPORTS = new Set(["run", "trail_run", "virtual_run", "walk"])

export function usesPace(sport) {
  return PACE_SPORTS.has(sport)
}
