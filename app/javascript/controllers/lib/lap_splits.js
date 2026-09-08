// Lap boundaries into one split per Tour, mirroring the shells' LapSplits.
// Laps arrive in the handoff and are rendered client-side; nothing here is
// persisted (docs/adr/0001-laps-stay-on-the-device.md).
//
// Splits are timed by temps écoulé, not durée de déplacement, so they agree
// with the timer the rider watched (CONTEXT.md).

// Below this a trailing lap is an artefact of tapping Tour just before Arrêter,
// not a lap anyone rode.
const EMPTY_LAP_DISTANCE = 1
const EMPTY_LAP_ELAPSED = 1

/** A ride that was never lapped is a single lap covering the whole ride. */
export function lapSplits({ boundaries = [], totalDistance = 0, totalElapsed = 0 }) {
  const ordered = [...boundaries].sort((a, b) => a.ordinal - b.ordinal)

  const splits = []
  let previousDistance = 0
  let previousElapsed = 0

  for (const boundary of ordered) {
    splits.push({
      ordinal: boundary.ordinal,
      // Totals and boundary rows are written a beat apart, so clamp.
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

export function splitAverageSpeed(split) {
  return split.elapsed > 0 ? split.distance / split.elapsed : 0
}
