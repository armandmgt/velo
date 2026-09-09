// Timed by temps écoulé, not durée de déplacement, so a split agrees with the
// timer the rider watched. Laps are never persisted server-side.

// Below this a trailing lap is an artefact of tapping Tour just before Arrêter.
const EMPTY_LAP_DISTANCE = 1
const EMPTY_LAP_ELAPSED = 1

export function lapSplits({ boundaries = [], totalDistance = 0, totalElapsed = 0 }) {
  const ordered = [...boundaries].sort((a, b) => a.ordinal - b.ordinal)

  const splits = []
  let previousDistance = 0
  let previousElapsed = 0

  for (const boundary of ordered) {
    splits.push({
      ordinal: boundary.ordinal,
      // Totals and boundary rows are written a beat apart.
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
