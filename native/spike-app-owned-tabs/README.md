# PROTOTYPE: app-owned tab bar hosting the mixed tabs (throwaway, never merged)

Spike for [Prototype an app-owned tab bar hosting the mixed tabs](https://github.com/armandmgt/velo/issues/11),
part of the map [Move the mobile apps off Hotwire Native](https://github.com/armandmgt/velo/issues/4).
Built on top of the first spike (`native/spike-mixed-tabs/`) on branch `prototype/native-mixed-tabs`.
Measured 2026-11-03 on an iPhone 17 Pro simulator (iOS 26.0, Hotwire Native iOS 1.3.0) and a
Pixel emulator (Hotwire Native Android 1.2.8).

## What was built

The app owns the tab bar on both platforms. Each tab still hosts a Hotwire `Navigator`, and
the Activités root is still the native list from the first spike, routed by path configuration.

| Piece | Where | Code lines |
|---|---|---|
| iOS: SwiftUI `TabView` with three hosted navigators, SwiftUI FAB and unsent badge | `native/ios/Sources/Spike/AppTabs.swift` | 173 (replaces the 228 of `RecordTabBarController`, now unused) |
| iOS: callers point at the new owner | `SceneDelegate`, `RecordingViewController`, `RecordingReviewComponent`, `NotificationCountComponent` | ±40 |
| Android: Compose `NavigationBar` replacing `HotwireBottomNavigationController` | `.../velo/spike/AppBottomBar.kt` | 97 |
| Android: wiring | `MainActivity` (6 lines), `activity_main.xml` (`BottomNavigationView` → `ComposeView`) | ±10 |

Android's FAB and badge stay where they were: they already lived in the activity layout,
outside Hotwire's controller.

## Results (Maestro)

| Scenario | iOS | Android |
|---|---|---|
| `auth_flow`, `auth_logout`, `fab_flow` | pass | pass |
| `record_flow`, `unsent_flow`, `restore_flow` (FAB, unsent badge, review hand-off, cross-tab after commit) | pass, after one fix (below) | pass |
| S1–S3: native root → web detail → back refetches | ✅ | ✅ |
| N1: reselecting the tab pops to its root | ✅ (written by hand) | ✅ (`clearAll`, as before) |
| S4 + N2: FAB "+" → modal over the native root; tab bar hidden under it | ✅ (free: the page sheet covers it) | ✅ (destination listener, as before) |
| S5: dashboard card → cross-tab into Activités, back → native root | ✅ | ✅ |
| S6: web link to `/activities` pops to the native root | ✅ | ✅ |
| S7: delete → 303 → pops, refetched, row gone | ✅ | ✅ |
| S9: sign out → sign in → native list loads | ✅ | ✅ |
| Back at a tab root | n/a | exits the app, same as before |
| iOS 26 `tabBarMinimizeBehavior(.onScrollDown)` on a web tab | ❌ the page scrolled 250 pt, the bar stayed | n/a |

Flows: `maestro/ios_walk.yaml` and `maestro/android_walk.yaml`. They need the dev server on
:3000 and two activities named "SPIKE delete me" (newest) and "SPIKE delete me 2". Seed them
with `Activity#dup` and `recording_uuid = nil`. The walk deletes the second one.

## What it cost

- **Record FAB and unsent badge.** iOS: rewritten in SwiftUI, about 70 lines, against about
  200 in UIKit. It dropped the forwarding tab-bar delegate, the `viewDidAppear` re-install,
  the off-window `CAAnimation` workaround and the iPad tab-bar pin. One trap: pulsing the
  opacity of the whole glass button made it **ignore taps**, which fell through to the web
  page below. Only `restore_flow` caught it (the FAB pulses only while recording). The fix
  was to pulse the glyph only. Android: no change.
- **Cross-tab routing.** Simpler on iOS: `model.selection = index` replaces `selectedIndex`
  plus the `UITab` mismatch workaround. Android: `routeInTab` and `TabRouteDecisionHandler`
  were unchanged.
- **Sign-in/out root swap.** Unchanged mechanism. iOS builds a fresh `AppTabsController` on
  each sign-in, which means fresh navigators, as `load(_:)` already did.
- **Hiding the bar on modals.** iOS: free. Android: about 10 lines copied from Hotwire's
  controller (destination listener, plus the keyboard insets listener).
- **Android back handling.** Unchanged, because `delegate.setCurrentNavigator` still decides
  which navigator gets Back.
- **New things to own:** pop-to-root on reselect (iOS), the slide animation (Android), and
  bar theming. The Compose selection pill falls back to the Material green, not the brand
  orange.

## What it buys

- **Tab chrome: little.** iOS 26's minimize-on-scroll didn't work on a web tab: SwiftUI doesn't
  see the `WKWebView` scroll view through the hosted navigator. UIKit's `UITabBarController`
  has the same iOS 26 APIs (`tabBarMinimizeBehavior`, bottom accessory) anyway. The selected
  accent works without the dark-mode workaround `RecordTabBarController` needed.
- **Ownership: a lot.** A tab no longer has to be a Hotwire navigator. A fully native tab is
  just another `TabView` / `NavigationBar` item. Selection, FAB mode and badge are plain
  observable state instead of hooks into Hotwire's non-`open` delegate. The shell no longer
  depends on Hotwire's tab API (`HotwireTabBarController`, `HotwireBottomNavigationController`),
  the part of the framework the app had to work around most.
- **Agent loop:** unchanged. Tab labels and FAB labels are still in the accessibility tree,
  so no flow needed new locators.
