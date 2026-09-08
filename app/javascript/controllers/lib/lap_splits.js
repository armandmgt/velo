// Turns a finished recording's lap boundaries into one split per Tour
// (#116, ADR 0003), mirroring the shells' `LapSplits`.
//
// Laps never reach the server — see `docs/adr/0001-laps-stay-on-the-device.md`.
// They arrive here in the handoff and are rendered client-side; nothing about
// this file is persisted, and no Activity carries a tour.
//
// A split is timed by **temps écoulé**, not durée de déplacement, so it always
// agrees with the timer the rider watched (see `CONTEXT.md`).

// Below this a trailing lap is an artefact of tapping Tour just before Arrêter,
// not a lap anyone rode.
const EMPTY_LAP_DISTANCE = 1
const EMPTY_LAP_ELAPSED = 1

/**
 * Expand cumulative boundaries plus the ride's totals into per-lap deltas.
 * Always returns at least one split for a recording that covered ground: one
 * that was never lapped is a single lap covering the whole ride.
 */
export function lapSplits({ boundaries = [], totalDistance = 0, totalElapsed = 0 }) {
  const ordered = [...boundaries].sort((a, b) => a.ordinal - b.ordinal)

  const splits = []
  let previousDistance = 0
  let previousElapsed = 0

  for (const boundary of ordered) {
    splits.push({
      ordinal: boundary.ordinal,
      // The totals and the boundary rows are written a beat apart, so clamp: a
      // split must never render as a negative distance.
      distance: Math.max(boundary.cumulativeDistance - previousDistance, 0),
      elapsed: Math.max(boundary.cumulativeElapsed - previousElapsed, 0),
    })
    previousDistance = boundary.cumulativeDistance
    previousElapsed = boundary.cumulativeElapsed
  }

  const trailing = {
    ordinal: (ordered.at(-1)?.ordinal ?? 0) + 1,
    distance: Math.max(totalDistance - previousDistance, 0),
    elapsed: Math.max(totalElapsed - previousElapsed, 0),
  }

  const isPhantom =
    splits.length > 0 &&
    trailing.distance < EMPTY_LAP_DISTANCE &&
    trailing.elapsed < EMPTY_LAP_ELAPSED
  if (!isPhantom) splits.push(trailing)

  return splits
}

/** Distance over temps écoulé (m/s); 0 for a split with no time on it. */
export function splitAverageSpeed(split) {
  return split.elapsed > 0 ? split.distance / split.elapsed : 0
}
