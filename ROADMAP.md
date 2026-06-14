# Route Planning — Roadmap

Planned routes let a user pick an activity type, drop waypoints on a map, and
get back a routed path that respects that sport's surface preferences (a road
bike avoids dirt, a gravel/MTB ride is happy on tracks, runners and hikers
use foot paths).

Routing engine: **BRouter** public server (`brouter.de/brouter`). Free, no
key, best-in-class cycling profiles. Easy to self-host later.

## PR 1 — MVP ✅ shipped

- `PlannedRoute` model + migration (PostGIS `LineString`, jsonb waypoints).
- `BRouterClient` + `RoutePlanner` (sport → profile mapping).
- `PlannedRoutesController` with index / new / create / show / destroy + a
  JSON `preview` endpoint used by the front-end as the user drops waypoints.
- New Stimulus controller `route_planner` for interactive waypoint placement.
- Reuses the existing `map_controller` for read-only display on the show page.

## PR 2 — Edit & polish ✅ shipped

- Edit existing planned routes: drag markers, click on the route to insert
  between waypoints, double-click (or right-click) to remove.
- Elevation profile chart on show page (and live in the form): generalized
  `elevation_profile_controller` to accept distance-based x-axis and a
  `coordinates` value, with chart-hover → map highlight via Stimulus outlet.
- Distance / elevation / waypoint stat cards on the show page, rendered via
  a shared `shared/_summary_metrics` partial that activities also use.
- Retry-able BRouter error alert: in-form DaisyUI `alert-error` with a
  Retry button that re-fires the preview, plus existing flash on submit.

## PR 3 — GPX & native polish

- "Export to GPX" download button (build a GPX `<trk>` from `path` points).
- Native nav-bar buttons (Save / Cancel) via `bridge--navbar-buttons`.
- Modal presentation on iOS/Android: add `/planned_routes/new` to
  `MODAL_PATTERNS` in `ConfigurationsController`.

## PR 4 — Parcours in the native tab bars

- Add a Parcours tab to the iOS `HotwireTabBarController` (rooted at
  `/planned_routes`) alongside the existing tabs, with an SF Symbol icon.
- Add the matching destination to the Android nav-graph + bottom navigation,
  using the same Material icon family as the other tabs.
- Drop the "Parcours" link from the user dropdown in `_navbar.html.erb` on
  native — the tab replaces it. Web users keep the dropdown entry.

## PR 5 — Sharing & library

- Public / unlisted planned routes (visibility enum).
- Import a planned route from a GPX upload.
- "Favorite" / "Reuse" flow — clone someone else's route into your library.

## Parking lot (out of scope until asked)

- Round-trip / loop generator ("give me a 30 km loop from here").
- Multi-modal segments (cycle to A, walk to B).
- Live turn-by-turn navigation in the native app.
- Self-hosting BRouter.
