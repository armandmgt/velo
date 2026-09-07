# Laps stay on the device

Native recording (#41) lets the rider mark laps ("Tour") while recording, and S12
surfaces each lap's split — distance, temps écoulé, average speed — during and
after the ride. Those laps are never uploaded: the S0 GPX contract
(`docs/native-recording/s0-gpx-upload-contract.md` §2) stays at a single
`<trkseg>`, and an Activity keeps no lap concept. A Tour is a property of a
recording session, and stops existing the moment that session becomes an
Activity.

## Considered Options

- **Carry laps to the server** — split the track into one `<trkseg>` per lap (or
  add a lap extension), teach `GpxExtractor` to read them, store them, render
  them on the activity page. Rejected for S12: it reopens a contract that a
  server fixture round-trips, and adds a table, extractor changes and web UI. That
  is an epic, not a polish story.
- **Live-only laps** — show splits in the recording dock and drop them at Stop.
  Rejected: the review screen, right before upload, is where a rider actually
  reads their splits.

## Consequences

A rider who laps a ride and then opens that ride on the web sees no splits
anywhere — the numbers exist only until upload. If laps ever do need to reach the
server, supersede this ADR and version the S0 contract rather than mutating it;
the fixture-proven single-`<trkseg>` shape is what makes the current upload path
safe to change around.
