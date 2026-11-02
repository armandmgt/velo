# Upstream Hotwire Native status on our failure classes

Research for [#6](https://github.com/armandmgt/velo/issues/6), part of map [#4](https://github.com/armandmgt/velo/issues/4).
Gathered 2026-11-02. Sources: the hotwire-native-ios and hotwire-native-android issue trackers, PRs and
release notes, upstream source on `main`, and native.hotwired.dev. Anything labelled **inference** is my
reading of upstream code, not something upstream has reported.

## TL;DR

| Failure class (our iOS symptom) | Upstream status | Fixed after our pin? |
|---|---|---|
| **Reload / back freezes until relaunch** | Known and open. iOS [#218](https://github.com/hotwired/hotwire-native-ios/issues/218): if a deploy changes a `data-turbo-track="reload"` asset, the restore visit gets invalidated and the app reloads the *wrong* (popped) screen. That leaves a spinner over a stale screenshot that never clears. Fix in **open, unmerged** PR [#270](https://github.com/hotwired/hotwire-native-ios/pull/270). | **No.** Not in any release. 1.3.x adds an offline variant of the freeze. |
| **Stuck loading on open (cold start)** | iOS 1.3.0 reworked cold-boot retry ([#231](https://github.com/hotwired/hotwire-native-ios/pull/231), [#247](https://github.com/hotwired/hotwire-native-ios/pull/247)). An iframe error can still fail a cold boot (open PR [#267](https://github.com/hotwired/hotwire-native-ios/pull/267)). Android has an open PR to recover when the WebView render process dies ([#222](https://github.com/hotwired/hotwire-native-android/pull/222)). | Partly (iOS 1.3.0) |
| **Stale content after background updates (title not updated)** | Upstream says refreshing a tab when you switch back to it is the **app's job** ([#221](https://github.com/hotwired/hotwire-native-ios/issues/221)). A tab hidden on iOS can miss broadcasts ([#176](https://github.com/hotwired/hotwire-native-ios/issues/176), closed without a fix). Stale-content bugs after modal redirects were fixed in 1.3.0/1.3.1 ([#241](https://github.com/hotwired/hotwire-native-ios/pull/241), [#261](https://github.com/hotwired/hotwire-native-ios/pull/261)). A stale snapshot after a redirect is still **open** ([#268](https://github.com/hotwired/hotwire-native-ios/pull/268)). | Partly |
| **Tab bar (`HotwireTabBarController`, flicker on tab change)** | 1.3.0 moved iOS tabs to the iOS 18 `UITab` API, where `viewControllers` and `selectedIndex` no longer track the selection ([#254](https://github.com/hotwired/hotwire-native-ios/issues/254)). Lazy tabs are opt-in on both platforms. No upstream flicker bug matches ours. **Inference:** our own `native-refresh` controller is the likeliest cause. | n/a (API change) |
| **Navbar menu inside sheets** | No upstream bug. Upstream offers no built-in "am I in a modal?" signal for web pages ([#203](https://github.com/hotwired/hotwire-native-ios/issues/203), closed without a fix). `Navigator.session`/`modalSession` became public ([#90](https://github.com/hotwired/hotwire-native-ios/pull/90)) so bridge components can tell. **Inference:** our own `_navbar` partial renders inside modal pages. | n/a (our bug) |

**Maintenance:** both repos are active, with commits from 37signals staff and HEY iOS as a downstream
consumer. But iOS releases are infrequent: 1.2.2 (Jul 2025) → 1.3.0 (Jul 2026), held back about 9 months
"until Android catches up". Several iOS fix PRs that apply to us have been open, without review, for
1–3 months. Android ships patch releases more often.

## Our versions

- **iOS**: `native/ios/project.yml` → `HotwireNative from: "1.3.0"`. In SPM that means "up to the next
  major", and `Package.resolved` is not committed (`/native/ios/Velo.xcodeproj/` is gitignored). So a
  fresh resolution, as in `fastlane beta`, picks up the latest 1.x, which is **1.3.1** today. This
  machine's DerivedData resolved **1.3.0**. We bumped from 1.2.2 to 1.3.0 in `ea29c16` to get
  `HotwireTabBarController.navigator(for:)`.
- **Android**: `native/android/app/build.gradle.kts` → `dev.hotwire:core` and `navigation-fragments`
  **1.2.8**. Latest is **1.3.2** (2026-10-12). We use `HotwireBottomNavigationController` (`MainActivity.kt`).

### Releases since our pins

**iOS** — [1.3.0](https://github.com/hotwired/hotwire-native-ios/releases/tag/1.3.0) (2026-07-07), [1.3.1](https://github.com/hotwired/hotwire-native-ios/releases/tag/1.3.1) (2026-08-14).

- 1.3.0 is large. The parts that matter to us:
  - lazy tabs, opt-in via `HotwireTabBarController(lazyLoadTabs:)`, default `false` ([#250](https://github.com/hotwired/hotwire-native-ios/pull/250), [#252](https://github.com/hotwired/hotwire-native-ios/pull/252));
  - `hideTabBarWhenPushed`;
  - `UITab`/`UISearchTab` on iOS 18+;
  - structured `HotwireNativeError`, plus a cold-boot retry fix: the Retry button used to do nothing when `topmostVisitable == nil`, and every error now gets a Retry button ([#231](https://github.com/hotwired/hotwire-native-ios/pull/231), [#247](https://github.com/hotwired/hotwire-native-ios/pull/247));
  - `refresh_historical_location` no longer restores from the snapshot cache ([#241](https://github.com/hotwired/hotwire-native-ios/pull/241));
  - modal redirect changes ([#154](https://github.com/hotwired/hotwire-native-ios/pull/154), [#251](https://github.com/hotwired/hotwire-native-ios/pull/251));
  - breaking: route decision handlers now receive a `VisitProposal`/`Navigating`.
- 1.3.1 includes:
  - [#253](https://github.com/hotwired/hotwire-native-ios/pull/253): bridge destinations stay active while their web view is attached. Before this, bridge messages sent during a tab or container `viewDidDisappear` were **dropped**.
  - [#261](https://github.com/hotwired/hotwire-native-ios/pull/261): a modal → default redirect is routed only after the dismissal completes. This was a 1.3.0 regression where HEY "lost a post-form redirect, leaving a stale list on screen".

**Android** — [1.3.0](https://github.com/hotwired/hotwire-native-android/releases/tag/1.3.0) (lazy bottom tabs [#202](https://github.com/hotwired/hotwire-native-android/pull/202); breaking changes: `RouteDecisionHandler` now takes a `VisitProposal`, and `debugLoggingEnabled` was replaced by `Hotwire.config.logger`), [1.3.1](https://github.com/hotwired/hotwire-native-android/releases/tag/1.3.1) ([#207](https://github.com/hotwired/hotwire-native-android/pull/207): a race after a modal `refresh` made the cold boot reload the *modal's* URL into the screen underneath), [1.3.2](https://github.com/hotwired/hotwire-native-android/releases/tag/1.3.2) (screenshot capture/memory fix [#217](https://github.com/hotwired/hotwire-native-android/pull/217); nested `NavigatorHost` graph fix [#220](https://github.com/hotwired/hotwire-native-android/pull/220)).

## 1. Freezes on reload / back / pull-to-refresh

**This is the best match for "reload sometimes freezes until relaunch" and for "stuck after the app was in
the background".**

- iOS [#218](https://github.com/hotwired/hotwire-native-ios/issues/218) (open, Jan 2026) has the symptom
  "page becomes unresponsive when navigating back, continuous loading indicator". The diagnosis appears
  in the issue comments and in [#208](https://github.com/hotwired/hotwire-native-ios/issues/208):
  1. A restore or back visit sees that a `data-turbo-track="reload"` fingerprint has changed.
  2. Turbo fires `pageInvalidated`, and `Session.webViewDidInvalidatePage` calls `reload()` on
     `topmostVisitable` (upstream `Session.swift`).
  3. During a pop, `topmostVisitable` is still the screen that is *leaving*, so that screen gets the
     cold boot.
  4. The revealed screen keeps its screenshot and spinner, and since the web view now sits in the popped
     controller, taps do nothing.
- One reporter: "a user has the app open, **we deploy**, and the first time they tap back the app freezes
  … customers reported this as 'the app hangs after it has been in the background for a while'". They
  also found a **1.3.1-only** variant: going back while offline freezes the same way, where 1.2.0 showed
  the error page with Retry.
- **Fix:** [hotwire-native-ios#270](https://github.com/hotwired/hotwire-native-ios/pull/270) (open since
  2026-10-18, no review yet) reloads the visitable of the *current* visit, which is what Android's
  `Session.pageInvalidated()` already does. **No iOS release contains it.**
- **Why this hits us:** `app/views/layouts/application.html.erb` marks `stylesheet_link_tag :app` and
  `"native"` with `data-turbo-track: "reload"`. Their digests change on **every Kamal deploy**, so every
  deploy arms this freeze for any iOS user with the app open.
- Workarounds named upstream:
  - keep tracked assets identical across pages (ours already are; only the deploy changes them);
  - drop `turbo-visit-control: reload`, which we don't use;
  - an app-side `requestDidFinish` check that reloads the visible controller when the URL doesn't match
    ([comment](https://github.com/hotwired/hotwire-native-ios/issues/208));
  - patch with #270.
- Older freezes, all fixed: [#88](https://github.com/hotwired/hotwire-native-ios/issues/88) (a frozen
  screenshot after a form submit and tab switching, where `appearReason == .tabSelected` skipped
  `visitableViewWillAppear`; fixed in [#91](https://github.com/hotwired/hotwire-native-ios/pull/91) and
  [#99](https://github.com/hotwired/hotwire-native-ios/pull/99), shipped in 1.2.0),
  [#92](https://github.com/hotwired/hotwire-native-ios/issues/92), and
  [#33](https://github.com/hotwired/hotwire-native-ios/issues/33).
  [#161](https://github.com/hotwired/hotwire-native-ios/issues/161) (an iOS 26 freeze on returning to a
  tab's root) was closed as server-side.
- **Pull-to-refresh, inference from upstream `main`.** `Session.visitableDidRequestRefresh` returns early
  when `visitable !== topmostVisitable`. In that case it never calls `visitableWillRefresh` or `reload()`,
  and the `UIRefreshControl` that the gesture already started is never ended. No upstream issue tracks
  this. It would produce a spinner that never finishes after a tab, modal or back race. Upstream has only
  [#146](https://github.com/hotwired/hotwire-native-ios/issues/146), "loader animation missing", which
  was closed for lack of a repro.
- Android [#206](https://github.com/hotwired/hotwire-native-android/issues/206) (open) reports that
  `data-native-prevent-pull-to-refresh` re-arms during multi-touch, such as pinching a map. That matters
  for our MapLibre screens.

## 2. Cold-start loading hangs

- iOS 1.3.0, [#231](https://github.com/hotwired/hotwire-native-ios/pull/231) and
  [#247](https://github.com/hotwired/hotwire-native-ios/pull/247):
  - a non-HTTP failure (status 0, timeout) now triggers one automatic cold-boot retry after a
    reachability check;
  - Retry used to be a **no-op** when there was no topmost visitable, i.e. on cold start, and now forces a
    cold boot;
  - every error type now gets a Retry button.
  Our iOS shell already implements the 1.3.0
  `visitableDidFailRequest(_:error:retryHandler:)` API.
- iOS [#267](https://github.com/hotwired/hotwire-native-ios/pull/267) (open): a non-2xx **iframe**
  response during the cold boot fails the whole visit, and the session never initializes. This applies
  only if a first-load page embeds third-party iframes. Our MapLibre maps use tiles over fetch, not
  iframes, so probably not us.
- iOS foreground handling: when the app returns to the foreground, `Navigator.appWillEnterForeground` →
  `inspectAllSessions()` recreates a web view whose content process was terminated. A web view killed in
  the background is reloaded on return (upstream `Navigator.swift`).
- Android [#143](https://github.com/hotwired/hotwire-native-android/issues/143) ("stuck on spinner after
  cold start", closed): caused by loading Turbo JS asynchronously. Our importmap loads it as a module,
  same as the demo.
- Android [#222](https://github.com/hotwired/hotwire-native-android/pull/222) (open, 2026-10-28): after
  the WebView render process dies, often while backgrounded, every tab stays blank or spinning until the
  activity is recreated. It isn't fixed in 1.3.2.
- No upstream issue matches "iOS sometimes stuck loading on open" by itself. The closest are the #218
  mechanism above (the deploy happens while the app is backgrounded) and the cold-boot retry gaps fixed
  in 1.3.0.

## 3. Stale content after background updates

**Upstream position: refreshing a tab when the user returns to it belongs in the app, not the library.**

- [#221](https://github.com/hotwired/hotwire-native-ios/issues/221) ("When navigating tabs … the screens
  don't refresh"). Joe Masilotti (maintainer): *"That's expected behavior. To refresh tabs you'll need to
  build something in your application code."*
- [#40](https://github.com/hotwired/hotwire-native-ios/issues/40) went the other way: every tab switch
  *used to* trigger a `.restore` reload. It was fixed in [#50](https://github.com/hotwired/hotwire-native-ios/pull/50)
  so that tabs keep their state.
- [#176](https://github.com/hotwired/hotwire-native-ios/issues/176) ("ActionCable disconnects on iOS
  apps") reports that broadcasts are not received in a non-selected tab on iOS but are on Android. It was
  closed as `waiting` with no fix. This matches the premise of our `native-refresh` controller.
- 1.3.1 [#253](https://github.com/hotwired/hotwire-native-ios/pull/253): before it, any bridge message
  sent while a tab or container controller was "disappeared" was dropped. That affects bridge-driven UI
  such as our `notification_count` badge, not Turbo Streams.
- Stale page after a modal or redirect. This is relevant if "naming from a notification" goes through the
  `/edit` modal, which `MODAL_PATTERNS` makes modal:
  - [#261](https://github.com/hotwired/hotwire-native-ios/pull/261) (1.3.1) fixed a **1.3.0 regression**:
    a modal → default redirect was dropped, leaving a stale list.
  - [#241](https://github.com/hotwired/hotwire-native-ios/pull/241) (1.3.0) fixed
    `refresh_historical_location` restoring from the snapshot cache (issues
    [#234](https://github.com/hotwired/hotwire-native-ios/issues/234) and
    [#224](https://github.com/hotwired/hotwire-native-ios/issues/224)).
  - Still open:
    - [#268](https://github.com/hotwired/hotwire-native-ios/pull/268): after a redirect, the adapter
      renders an older cached snapshot *over* the fresh response, because the iOS `turbo.js` calls
      `loadCachedSnapshot` after `issueRequest`. Turbo's own BrowserAdapter uses the opposite order.
    - [#178](https://github.com/hotwired/hotwire-native-ios/issues/178): a stale snapshot when
      redirecting to a URL already on the stack.
    - [#266](https://github.com/hotwired/hotwire-native-ios/issues/266) and
      [#244](https://github.com/hotwired/hotwire-native-ios/issues/244): 1.3.0 regressions around form
      redirects into modals.
  - Android [#153](https://github.com/hotwired/hotwire-native-android/issues/153) (open):
    `refresh_historical_location` from a bottom-sheet modal refreshes the wrong URL. Partly addressed by
    1.3.1 [#207](https://github.com/hotwired/hotwire-native-android/pull/207).
- Docs: [Navigation reference](https://native.hotwired.dev/reference/navigation) only says that
  `refresh_or_redirect_to` "reloads the visible screen … invalidating the cache". The docs say nothing
  about stale tabs, background updates or snapshots.

## 4. Tab bar controllers and flicker on tab change

- iOS 1.3.0 builds tabs with the iOS 18+ `UITab` API (`self.tabs` / `selectedTab`) instead of
  `viewControllers` (upstream `HotwireTabBarController.swift`). Maintainer svara in
  [#254](https://github.com/hotwired/hotwire-native-ios/issues/254) (an infinite loop after upgrading to
  1.3.0): `tabs` and `viewControllers` "are no longer kept in sync", so don't infer state from
  `viewControllers`.
  - **Inference for us:** `RecordTabBarController` already resolves the current tab through
    `activeNavigator` for this reason. But `SceneDelegate` still *reads* and *sets*
    `tabBarController.selectedIndex` for cross-tab routing and sign-in, and
    `NotificationCountComponent` / `RecordingReviewComponent` set it too. That is worth auditing against
    `selectedTab`.
- Tabs need `load(_:)` again after login ([#181](https://github.com/hotwired/hotwire-native-ios/issues/181)).
  We do this in `didSignIn`.
- Lazy tabs are opt-in on both platforms: iOS `HotwireTabBarController(lazyLoadTabs: true)`, Android
  `HotwireBottomNavigationController(lazyLoadTabs = true)`. Both default to eager
  ([iOS docs](https://native.hotwired.dev/ios/tabs), [Android docs](https://native.hotwired.dev/android/tabs)).
  Each iOS tab owns a `Navigator` with its own `session` and `modalSession`, so it has two web views.
- Open Android PR [#186](https://github.com/hotwired/hotwire-native-android/pull/186) would support
  `NavigationRailView`. Neither the iOS nor the Android docs mention refreshing tabs or preserving state.
- **Flicker: no matching upstream issue.** The closest are
  [#53](https://github.com/hotwired/hotwire-native-ios/issues/53) (replace visits flash; closed) and
  [#173](https://github.com/hotwired/hotwire-native-ios/issues/173) (HTML tab bar animation). Our likely
  cause is `app/javascript/controllers/native_refresh_controller.js` (**inference**):
  - It runs `Turbo.visit(location, {action: "replace"})` on every `visibilitychange` → visible, which
    includes each tab switch and each return to the foreground.
  - Upstream `turbo.js` handles a same-URL proposal as an in-place refresh (`visitProposalRefreshingPage`),
    so no new controller is pushed.
  - But `Session.visitWillLoadResponse` still snapshots the page and overlays the screenshot while the
    morph happens, even for page refreshes. Only `visitWillStart`/`visitDidStart` skip page refreshes.
  - So each tab switch produces a screenshot swap plus a network round-trip, which could read as a
    flicker. It also starts a visit that can race a pull-to-refresh or an incoming stream `refresh`.

## 5. Modal / sheet navbar items

- Upstream has no bug about bar buttons leaking into sheets. Options upstream provides:
  - `Hotwire.config.showDoneButtonOnModals` adds a Done button
    ([iOS configuration](https://native.hotwired.dev/ios/configuration)).
  - Path configuration covers `context: modal`, plus `modal_style` and `modal_dismiss_gesture_enabled`
    on iOS ([path configuration](https://native.hotwired.dev/reference/path-configuration)).
- There is no built-in way for a web page to know it is in a modal:
  - [#203](https://github.com/hotwired/hotwire-native-ios/issues/203) asked for a header and a
    `hotwire_native_modal?` helper; it was closed without one.
  - [#89](https://github.com/hotwired/hotwire-native-ios/issues/89) → [#90](https://github.com/hotwired/hotwire-native-ios/pull/90)
    made `Navigator.session` and `modalSession` public, so a native bridge component can check whether
    its web view belongs to the modal session.
- **Inference for us:** `app/views/application/_navbar.html.erb` holds `data-controller="bridge--navbar-buttons"`
  and is rendered by the layout on *every* signed-in page, including pages presented as modals. Our
  `NavbarButtonsComponent` then puts the kebab menu on the modal controller's `navigationItem`. This is our
  bug, not upstream's. Fix it on the web side (skip `_navbar` when the path matches `MODAL_PATTERNS`) or
  in the component (ignore it when `delegate.destination` is in the modal session or has a
  `presentingViewController`).
- Related 1.3.x modal regressions that are still open:
  - [#266](https://github.com/hotwired/hotwire-native-ios/issues/266): a main-stack form that redirects to
    a modal pops the presenting screen.
  - [#257](https://github.com/hotwired/hotwire-native-ios/issues/257): large titles collapse on pushed
    screens since 1.3.0.

## Maintenance signals

- **hotwire-native-ios**:
  - 311★, 24 open issues.
  - Release history: 1.0.0 in Sep 2024 → 1.2.2 in Jul 2025, then a 1.3.0-beta in Sep 2025. The final
    1.3.0 waited until Jul 2026; Joe Masilotti in [#235](https://github.com/hotwired/hotwire-native-ios/issues/235):
    "holding off on releasing it until Android catches up".
  - The latest release is 1.3.1 (2026-08-14), and `main` has had no commits since.
  - Merges come almost entirely from one maintainer (svara). Other contributors include joemasilotti,
    olivaresf and josefarias, with HEY iOS as a named consumer ([#261](https://github.com/hotwired/hotwire-native-ios/pull/261)).
  - Fix PRs that matter to us are open with no review: #262, #267, #268 and #270, all from Aug–Oct 2026.
    Nine PRs are open in total.
  - Triage pattern: issues that can't be reproduced in the demo app get closed (#146, #161, #245).
- **hotwire-native-android**:
  - 169★, 24 open issues.
  - Steadier patch releases: 1.2.5 to 1.2.8 between Jan and May 2026, then 1.3.0 to 1.3.2 between Jul and
    Oct 2026.
  - `main` was pushed on 2026-11-02; maintainers are mbarta and jayohms.
  - Open PRs include render-process recovery (#222) and an Activity/WebView leak fix (#221).

## What this means for #4

1. **The worst bug, the freeze, has a known upstream cause and an unmerged fix** (#270). Each Kamal deploy
   can trigger it, because of our `data-turbo-track="reload"` stylesheets. We can stay on the hybrid and
   still fix it: vendor or patch #270, or add the app-side `requestDidFinish` guard. Either is cheap
   compared with going native.
2. **Stale tabs are by design upstream.** Any hybrid fix stays app-side (our `native-refresh`). A
   native-screen design needs its own refetch-on-focus anyway (the map's "Live updates on native screens"
   item).
3. **The sheet navbar and the probable tab flicker are our code**, not Hotwire Native's.
4. iOS floats on `from: "1.3.0"` with no lockfile, so local, fastlane and device builds can run different
   1.3.x versions. Commit a `Package.resolved` or use an exact pin, whatever the decision. Android is two
   minor versions behind (1.2.8 vs 1.3.2), with breaking changes to route decision handlers and logging.
5. iOS release cadence is the risk to weigh: fixes we need can sit unreleased for months, so staying hybrid
   probably means pinning to a commit or carrying patches.
