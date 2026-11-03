# PROTOTYPE: native screen inside the Hotwire tabs (throwaway, never merged)

Spike for [Prototype a native tab bar hosting the Hotwire tabs](https://github.com/armandmgt/velo/issues/8),
part of the map [Move the mobile apps off Hotwire Native](https://github.com/armandmgt/velo/issues/4).
Branch `prototype/native-mixed-tabs`, cut from `main` at 526880d. Measured 2026-11-03 on an
iPhone simulator (Hotwire Native iOS 1.3.0) and a Pixel 6 emulator (Hotwire Native Android 1.2.8).

## What was built

The Activités tab's root (`/activities`) is a native screen on both platforms. It's a rough SwiftUI
list on iOS and a Compose list on Android. Tapping a row routes the activity's URL through the
tab's Hotwire `Navigator`, which pushes the web detail page onto the same stack. The tab bar is
still Hotwire's (`HotwireTabBarController`, `HotwireBottomNavigationController`). We didn't need
an app-owned SwiftUI `TabView` or Compose bottom bar.

| Piece | Where | Size |
|---|---|---|
| Route `/activities` to native | `ConfigurationsController`: `view_controller: "activities_native"` (iOS), `uri: "hotwire://fragment/activities_native"` (Android) | 2 rules |
| iOS hook | `SceneDelegate.handle(proposal:)` returns `.acceptCustom(SpikeActivitiesViewController(navigator:))` | 4 lines |
| iOS screen | `native/ios/Sources/Spike/ActivitiesNativeScreen.swift` (`UIHostingController` + `@Observable` model) | 96 lines |
| Android hook | register `SpikeActivitiesFragment` in `Hotwire.registerFragmentDestinations` | 1 line |
| Android screen | `.../velo/spike/SpikeActivitiesFragment.kt` (`HotwireFragment` + `ComposeView`) | 119 lines |
| Data | `app/views/activities/index.json.jbuilder`, authenticated by the webview's session cookie | 11 lines |

Other changes, also throwaway:
- Herb debug mode and Hotwire Spark are off in development, to keep native runs production-like (see the diagnosis ticket).
- `activities/show` has copies of its bottom links at the top, because Maestro can't scroll past the map.

## Results (Maestro, both platforms unless noted)

| # | Scenario | iOS | Android |
|---|---|---|---|
| S1 | Native list renders as the tab root | ✅ | ✅ |
| S2 | Row → web detail pushed on the same stack (back button, web "More" menu) | ✅ | ✅ |
| S3 | Back → native list refetches (`viewWillAppear` / `onStart`) | ✅ fetch #2 | ✅ fetch #2 |
| S4 | FAB "+" on the native tab → `/activities/new` modal over it, dismiss | ✅ | ✅ |
| S5 | Dashboard card → cross-tab routing into the Activités tab, back → native root | ✅ | ✅ |
| S6 | Web link to `/activities` from the detail page → **pops** to the native root (no duplicate list) | ✅ | ✅ |
| S7 | Delete on the detail page → 303 to `/activities` → pops to the native root, refetched, row gone | ✅ | ✅ |
| S9 | Sign out from the dashboard menu → sign in → native list loads with the new cookie | ✅ | ✅ (signed in again after the revoke, native list loaded) |
| S10 | Session revoked server-side → `/activities.json` answers **302 to the HTML login page**, and the native screen has no way back to sign-in | ❌ by design | same server answer |
| E2 | Deploy-then-tap (fingerprint change, then open an activity from the native list) | 0 stuck in 6 runs (2 GETs each) | not run (Android never froze in the diagnosis) |

Why S6 and S7 work: Hotwire 1.3 tags *every* routed controller with its URL (`routedLocation`),
custom ones included. A visit to the previous controller's URL therefore pops, and a native
screen takes part in that like a web one. Android behaves the same way.

Existing regression flows: `auth_flow`, `auth_logout` and `fab_flow` pass on both platforms.
`activities_list` fails at its dashboard step, but that step was already broken on `main`: the
dev data now has newer rides than its pinned 30 June date. Its Activités half would fail by
design, since it asserts web card text.

## What breaks or costs

- **The web navbar menu doesn't exist on native screens.** The "More"/"Menu" items and the
  notification bell come from the `bridge--navbar-buttons` / `notification-count` components,
  which need a web page. A native screen has to supply its own nav bar items, or the tab loses
  them. Today the Activités root shows no menu at all.
- **Native screens need their own auth failure path.** A revoked or expired session answers 302
  → HTML. The API must answer 401, and the native screen must hand off to sign-in itself:
  `is_after_sign_out_path` only works for web visits.
- **Redirects to a native-backed URL still render the HTML page.** After the delete, the web
  view fetched `GET /activities` (full HTML) before the proposal was handed to the native
  screen. So the HTML route must keep working: the web needs it anyway.
- **Live updates become refetch-on-reveal.** No Turbo Stream reaches the native list. Refetching
  on `viewWillAppear` / `onStart` was enough for every scenario above.
- **FAB, record flow, cross-tab routing and modals needed no changes**, because the tab bar and
  the per-tab `Navigator`s stay Hotwire's.
- **Agent loop:** native screens give stable ids (`spikeActivityRow`, `spikeNativeMarker`) and
  deterministic assertions such as `fetch #2`. The hybrid side kept its traps: on both platforms
  Maestro can't scroll a web page whose middle is a MapLibre map, and on iOS a swipe that starts
  on the tab bar pops the tab to its root.

## Flows

`maestro/`: throwaway flows used above. They are paths relative to this folder, not a suite.
They expect the dev server on :3000 and a signed-in dev user. The deploy probe
(`e2_warm` → append a comment to `app/assets/stylesheets/native.css` → `e2_tap`, then count
`GET /activities/172` in the log) was driven from the shell.
