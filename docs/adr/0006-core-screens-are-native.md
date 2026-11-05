# Core screens are native; the long tail stays Hotwire

The mobile apps move their core screens to SwiftUI (iOS) and Jetpack Compose
(Android), inside an app-owned tab bar, and keep Hotwire Native for everything
else. Fixing the hybrid in place was the cheaper option and was rejected. The
deciding criterion is the **agent feedback loop**: Velo is maintained solo and
only through agents, and a change is only safe if an agent can get a
deterministic pass/fail from a CLI check without a human looking at a device.

## Why not just fix the hybrid

A diagnosis of the iOS failures found that four of five were our own code and
cheap to fix. Those fixes happen anyway. Fixing them still leaves every screen
testable only on a device against a live server, where failures show up as
navigation timing. Native SwiftUI and Compose screens meet the bar: Compose runs
on the JVM (Robolectric + Roborazzi), SwiftUI on a pinned simulator (Swift Testing +
swift-snapshot-testing), and Maestro stays as the slow end-to-end layer. A
native tab bar alone ("option b") changes none of this, because every failure
sits below the tab bar.

## Which screens are native

A screen goes native when it is a **tab root**, a **daily destination**, or
something the hybrid loop **cannot test** (maps, charts, gestures). Plain forms
(settings, gear, imports, admin, auth, edit/new pages) stay Hotwire for good:
they change most, gain least, and Hotwire handles them well.

Store v1 ships with native versions of: Tableau de bord, the Activités list,
activity detail, the route planner (new and edit itinéraire, GPX import
included), and the recording screen, which was already native. The Itinéraires
list and detail, Forme, Records and Heatmap stay Hotwire in v1 and migrate later
under the same rule. The route planner is a map editor, not a form; on a phone
the web version's panels cover the map, and dragging or inserting waypoints is
hard.

## Consequences worth knowing

- iOS and Android migrate together, screen by screen. Cross-platform frameworks
  were ruled out.
- The web stays a first-class product. The native apps become a second client
  of the same Rails backend, through a JSON API beside the HTML views. HTML
  routes behind native screens must keep working, because redirects still
  render them in a web view.
- ADR 0003 stands for v1: the recording review stays the web `/activities/new`.
- Hotwire Native stays a dependency. Its iOS deploy freeze
  (hotwire-native-ios#218) is handled by pinning a fork that carries the
  unmerged fix #270.
