# Native screens navigate through Hotwire's Navigator

The native SwiftUI / Compose screens from [ADR 0006](0006-core-screens-are-native.md)
don't use `NavigationStack` or a Compose nav graph. Each tab of the app-owned tab bar
keeps a Hotwire `Navigator`, and a native screen is one of its destinations, routed
by URL through path configuration. In store v1, most navigation crosses the
native/web line: web pages link to activity detail, Hotwire pages open the native
planner, and native screens open Hotwire forms. The `Navigator` already handles all
of it: pushes, pop-back-to-an-open-URL, redirect pops, cross-tab routing and modals.
A native stack would have to intercept every web link and host Hotwire pages inside
SwiftUI / Compose navigation, which Hotwire doesn't support.

## Consequences worth knowing

- A native screen never builds the next screen. It hands a URL to an injected
  router. Tests assert those URLs with a fake router, Rails tests cover the
  path-configuration routing, and Maestro covers the full hop.
- Path configuration decides which URLs are native, so it's versioned per build:
  a build that adds native destinations fetches a new config (`ios_v2`,
  `android_v2`), and older builds keep the previous one and its web pages.
- Native screens have no web navbar. The global menu is a "⋯" button the app
  draws on the tab roots only, with its items coded in the app. The "sorties à
  nommer" bell becomes a count badge on the Tableau de bord tab.
- A tab-owned native stack is worth revisiting only for a tab that can't reach
  any web page.
