# Route Planning — Roadmap

Planned routes let a user pick an activity type, drop waypoints on a map, and
get back a routed path that respects that sport's surface preferences (a road
bike avoids dirt, a gravel/MTB ride is happy on tracks, runners and hikers
use foot paths).

Routing engine: **BRouter** public server (`brouter.de/brouter`). Free, no
key, best-in-class cycling profiles. Easy to self-host later.

## PR 1 — MVP (this PR)

- `PlannedRoute` model + migration (PostGIS `LineString`, jsonb waypoints).
- `BRouterClient` + `RoutePlanner` (sport → profile mapping).
- `PlannedRoutesController` with index / new / create / show / destroy + a
  JSON `preview` endpoint used by the front-end as the user drops waypoints.
- New Stimulus controller `route_planner` for interactive waypoint placement.
- Reuses the existing `map_controller` for read-only display on the show page.

## PR 2 — Edit & polish

- Edit existing planned routes (drag waypoint markers, insert between, remove).
- Elevation profile chart on show page (reuse `elevation_profile_controller`).
- Distance / elevation stat cards on the show page (reuse the
  `activity_summary_metrics` look).
- Routing-error UX: toast + retry when BRouter returns no-route or 5xx.

## PR 3 — GPX & native polish

- "Export to GPX" download button (build a GPX `<trk>` from `path` points).
- Native nav-bar buttons (Save / Cancel) via `bridge--navbar-buttons`.
- Modal presentation on iOS/Android: add `/planned_routes/new` to
  `MODAL_PATTERNS` in `ConfigurationsController`.

## PR 4 — Activity integration

- "Start from this route" button on the planned-route show page.
- When viewing a past activity, optionally overlay the linked planned route
  (planned vs. actual).
- `Activity belongs_to :planned_route, optional: true` (nullable FK).

## PR 5 — Sharing & library

- Public / unlisted planned routes (visibility enum).
- Import a planned route from a GPX upload.
- "Favorite" / "Reuse" flow — clone someone else's route into your library.

## Parking lot (out of scope until asked)

- Round-trip / loop generator ("give me a 30 km loop from here").
- Multi-modal segments (cycle to A, walk to B).
- Live turn-by-turn navigation in the native app.
- Self-hosting BRouter.
