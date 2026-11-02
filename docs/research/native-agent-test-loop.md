# Agent test loop for SwiftUI and Compose

Research for [#7](https://github.com/armandmgt/velo/issues/7), part of the map [#4](https://github.com/armandmgt/velo/issues/4).
Researched 2026-11-02 against Xcode 27.1, Compose BOM 2026.06, AGP 9.x.

**The question.** What verification loop do SwiftUI (iOS 17+) and Jetpack Compose give
an agent that works only from the command line, compared with today's Hotwire Native
loop? **The bar:** the agent makes a change, runs a CLI check, and gets a deterministic
pass or fail without a human looking at the device.

## TL;DR

- **Both platforms clear the bar for state and rendering, and neither needs a device
  for most of it.** The failures we see today come from timing between the native
  shell and a WebView. Native screens move most of that risk into code that a
  synchronous, in-process test can reach.
- **Android has the better loop.** Compose UI tests and screenshot tests run on the JVM
  under Robolectric, with no emulator. They use a virtual clock that waits for the UI to
  go idle, and they can dump the semantics tree as text. One Gradle command gives a
  pass or fail. The repo already runs Robolectric 4.16 in `app/src/test`.
- **The existing iOS unit suite is flaky today.** It passed 1 run in 5 here. The test
  host is the whole app, so the Hotwire shell boots during the run and a Core Data
  observer crashes it. See [Measured here](#measured-here). Android's suite was green on
  every run.
- **The iOS loop is good but always needs a simulator.** `xcodebuild test` runs Swift
  Testing plus [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
  on a booted simulator. It is deterministic only when the simulator model and OS are
  pinned. SwiftUI previews **cannot** be rendered headlessly in CI. Xcode's MCP
  `RenderPreview` needs the Xcode app running with the project open.
- **Maestro stays as the end-to-end layer, and gets more reliable on native views.**
  Maestro reads the accessibility tree. SwiftUI and Compose expose stable
  identifiers (`accessibilityIdentifier`, `testTag`/semantics), so flows can target
  them instead of WebView text, and fewer flows have to wait out WebView transitions.
  Maestro is still the slowest and least deterministic layer, so it should guard
  flows. It should not be the agent's inner loop.

### Recommended loop

| Layer | iOS (SwiftUI) | Android (Compose) | Runs on | Result |
|---|---|---|---|---|
| 1. State / ViewModel | Swift Testing on `@Observable` models, `xcodebuild test -only-testing VeloTests/…` | JUnit (+ Robolectric only where Android APIs leak), `./gradlew :app:testDebugUnitTest` | iOS: simulator (app-hosted). Android: JVM | Text: `#expect` / assert diffs |
| 2. Screen behaviour | XCUITest only for the few cross-screen flows (out-of-process, slower). Otherwise covered by 1 + 3 | Compose UI tests in `src/test` under Robolectric (`createComposeRule`) | iOS: simulator. Android: JVM | Text: assertion + `printToString()` semantics tree |
| 3. Rendering | swift-snapshot-testing `.image(layout:)` + a text strategy (`.dump` / `.recursiveDescription`) | Roborazzi (`captureRoboImage`, `verifyRoborazziDebug`), or Compose Preview Screenshot Testing | iOS: pinned simulator. Android: JVM | Pass/fail + image diff on disk; Roborazzi also a `*.uitree.json` |
| 4. End-to-end | Maestro flows (existing `native/ios/maestro`) | Maestro flows (existing `native/android/maestro`) | Simulator / emulator + Rails | Pass/fail + hierarchy JSON |
| Agent's eyes (not a gate) | Xcode MCP `RenderPreview` (Xcode open) | `android studio render-compose-preview --print-semantics` (Studio open) | IDE running | PNG + (Android) semantics JSON |

An agent's inner loop is layers 1–3. Layer 4 runs before a PR, the way it does today.

## What the repo has today

- **iOS unit tests.** `native/ios/Tests/*.swift`, six suites: recording restore,
  auto-pause, lap splits, heart rate, handoff, route bounds. They use **Swift Testing**
  (`import Testing`, `@Suite`, `#expect`) in the `VeloTests` bundle, which
  `native/ios/project.yml` hosts in the app target "so Core Data-backed helpers can be
  exercised against the real bundled model." So they already need a simulator. The
  `mise` tasks have no test task (`native/ios/mise.toml` has `simulator`, `debug`,
  `testflight`, `release`).
- **Android unit tests.** `native/android/app/src/test/kotlin/.../features/record/*Test.kt`,
  five classes. JUnit4 plus Robolectric 4.16 run "against the code that ships rather
  than against fakes" (`app/build.gradle.kts`, which also sets
  `unitTests.isIncludeAndroidResources = true`). Compose (BOM 2026.06.00) is already in
  the build for the recording screen, but there are no Compose UI tests and no
  screenshot tests yet.
- **Maestro flows.** Seven mirrored flows per platform plus subflows in
  `native/{ios,android}/maestro/`. They run against a booted device with the debug build
  installed and `bin/dev` running (`native/ios/maestro/README.md`). They are already
  full of hybrid-timing workarounds:
  - `record_flow.yaml` needs `waitForAnimationToEnd` before WebView assertions,
    "or the first query races it and reads as not-visible".
  - It needs `extendedWaitUntil … timeout: 30000` for the web review modal.
  - It uses case alternations (`"TEMPS ÉCOULÉ|Temps écoulé"`) because CSS-uppercased
    text surfaces differently on iOS and Android.
  - It notes that "Maestro's iOS driver cannot traverse a sheet presented over the
    full-screen recording modal". That limitation affects native UIKit too, not only
    the WebView.
- **CI.** `.github/workflows/ci.yml` runs only Ruby, JS and Rails jobs. **No native job
  exists**, so today nothing native gates a PR.

## Today's Hotwire Native loop, and why it misses the bar

- **Rails tests only cover the web.** Rails system tests (Capybara) drive a desktop
  browser. They never exercise the native visit lifecycle, path-configuration routing,
  modals or tab-bar swaps. "Web tests pass, failures live in native navigation timing"
  (map #4).
- **The bugs live in the gaps between the shell and the WebView.** Recent fixes show
  the class:
  - [`e2637f1`](https://github.com/armandmgt/velo/commit/e2637f1): a tab-tap SIGABRT
    in `RecordTabBarController`. Hotwire "resets delegate=self right after
    super.init", and `selectedIndex` "doesn't track the selection on iOS 18+ UITab
    bars".
  - [`ea5f0ee`](https://github.com/armandmgt/velo/commit/ea5f0ee): backgrounded tabs'
    web views drop ActionCable, so they go stale.

  Both are lifecycle and timing bugs. No test that runs inside one process can see them.
- **Only an emulator can test it, and the Android test docs confirm that.** Robolectric
  "doesn't support … `WebView`", so WebView-backed behaviour needs device tests
  ([Android: Robolectric](https://developer.android.com/training/testing/local-tests/robolectric)).
  That leaves Maestro or XCUITest/Espresso on a real simulator, against a live Rails
  server, waiting on WebView loads. That is exactly where the repo's flows need sleeps,
  long timeouts and tolerant regexes.
- **Maestro's tolerance hides the problem.** Maestro says it "automatically handl[es]
  flakiness and UI settling" and "waits for network content and animations"
  ([What is Maestro](https://docs.maestro.dev/get-started/what-is-maestro.md)). That
  helps end-to-end checks pass. The flip side is that a real timing bug can pass
  because Maestro waited it out, and a slow page can fail when it outlasts the timeout.

## Per-technique findings

Speed figures are relative orders of magnitude: they come from the architecture
(JVM vs simulator vs out-of-process), not from benchmarks. The one figure measured
here is noted.

### iOS

#### Swift Testing / XCTest on state (ViewModels, `@Observable`)

- **How it runs.** `xcodebuild test -scheme Velo -destination … -only-testing VeloTests/<Suite>`.
  `-only-testing` narrows the run to a target, suite or test. `-test-iterations` with
  `-run-tests-until-failure` re-runs a test to prove it reliable. Each run writes an
  `.xcresult` bundle
  ([Apple: Running tests and interpreting results](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results.md)).
- **Speed.** The tests themselves take milliseconds. The cost is build, install and app
  launch, about 48 s warm here, because `VeloTests` is app-hosted. Moving pure logic (view models, formatters, API decoding)
  into a local Swift package that also builds for macOS would allow `swift test` on the
  host, with no simulator. That is a design option, not something the repo does today.
- **Determinism.** High in principle, as long as the code doesn't touch wall-clock time
  or networking. Inject clocks and API clients. In practice, an app host undermines it:
  Velo's current hosted suite is flaky (see [Measured here](#measured-here)). This is the same discipline the
  recording tests already follow, for example `RecordingStore(inMemory: true)`.
- **Readable by an agent.** Yes. `#expect` failures print the expression and the values
  it captured (same Apple doc).

#### swift-snapshot-testing (Point-Free), latest 1.19.7 (2026-10-21)

- **How it runs.** It is an ordinary test, so it runs under `xcodebuild test`. SwiftUI
  views use `assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))`.
  The `layout` options are `.device(config:)`, `.fixed(width:height:)` and
  `.sizeThatFits`. You can also pass `precision`, `perceptualPrecision` and `traits`
  ([`SwiftUIView.swift`](https://github.com/pointfreeco/swift-snapshot-testing/blob/main/Sources/SnapshotTesting/Snapshotting/SwiftUIView.swift)).
- **Text strategies.** `.dump` (any value, through its mirror) and
  `.recursiveDescription` (views and view controllers) produce text snapshots that show
  as inline diffs ([README](https://github.com/pointfreeco/swift-snapshot-testing)).
- **Recording references.** Recording is controlled per suite with
  `@Suite(.snapshots(record: .failed))`, or with the `SNAPSHOT_TESTING_RECORD`
  environment variable (read in `AssertSnapshot.swift`). With that variable an agent can
  re-record from the CLI: `SNAPSHOT_TESTING_RECORD=failed xcodebuild test …`.
- **Swift Testing.** Supported (README).
- **Determinism.** The README warns that "snapshots must be compared using the exact
  same simulator that originally took the reference". So the simulator model, iOS
  runtime and Xcode version must be pinned, the same locally and in CI. An Xcode
  upgrade means a deliberate re-record. `perceptualPrecision` (for example 0.98)
  absorbs anti-aliasing noise.
- **Map views are a caveat.** MapLibre map views load tiles over the network. Snapshot
  the dock and controls around a placeholder, not the live map. This is inferred, not
  tested.
- **Speed.** Fast once the simulator is booted. The image render happens in-process.
- **Readable by an agent.** The pass or fail is text. Image diffs are "captured as
  XCTest attachments" in the `.xcresult`. An agent can extract them with
  `xcrun xcresulttool` and read the PNG, but a text strategy alongside the image is
  what makes most failures legible without vision.

#### ViewInspector (third-party)

- **What it does.** It traverses a SwiftUI view hierarchy at runtime with Swift's
  reflection API. You find views, read their state and tap buttons in a unit test
  ([nalexn/ViewInspector](https://github.com/nalexn/ViewInspector), v0.10.6).
- **Limits.** Coverage varies by view and modifier.
- **Worth it?** It is optional. Testing the `@Observable` model directly plus snapshots
  usually covers the same ground with less coupling to view internals.

#### SwiftUI previews rendered headlessly: not possible for CI

- **No official headless renderer exists.** Apple's only programmatic preview path is
  the Xcode MCP server, reached through `xcrun mcpbridge`. Apple's instructions:
  turn on "Allow external agents to use Xcode tools" in Intelligence settings, run
  `claude mcp add --transport stdio xcode -- xcrun mcpbridge`, and "before prompting an
  external agent … be sure to open your project in Xcode"
  ([Apple: Giving external agents access to Xcode](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode.md)).
- **Local check.** `xcrun mcpbridge --help` on Xcode 27.1 describes it as a "STDIO
  Bridge for Xcode MCP Tools" that connects to a running Xcode, with `MCP_XCODE_PID` to
  pick which one.
- **RenderPreview.** The tool list isn't in Apple's public docs. Third-party
  integrations list a `RenderPreview` tool that captures a preview screenshot
  ([Cursor: Xcode integration](https://cursor.com/docs/integrations/xcode)). This is
  secondary and unverified.
- **Verdict.** It is useful as the agent's eyes on a developer machine. It needs a GUI
  Xcode session and returns an image, not a verdict, so it is **not a gate**. For a
  gate, turn previews into snapshot tests.

#### XCUITest

- **How it works.** UI tests run "as a separate process, synthesizing events that UI in
  your app responds to", through Accessibility, using `XCUIApplication`,
  `XCUIElement` and `XCUIElementQuery`
  ([Apple: User Interface Testing (archive)](https://developer.apple.com/library/ios/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html)).
  The test can't reach app state directly, so it configures the app through launch
  arguments and environment.
- **Determinism.** Medium. It waits on the accessibility tree, so you still write
  `waitForExistence`-style waits. Pure-SwiftUI screens with `accessibilityIdentifier`
  are far steadier than WKWebView content.
- **Speed.** Slowest of the Xcode options: app launch per test, out-of-process queries.
- **CI.** CI-friendly on macOS runners via `xcodebuild test`.
- **Readable by an agent.** Text failures, plus screenshots in the `.xcresult`.
- **Against Maestro.** It overlaps Maestro, which the repo already uses and keeps
  mirrored across platforms. Pick one end-to-end tool per platform. Maestro wins on
  being mirrored and needing no compile; XCUITest wins when a flow needs in-process
  fixtures.

### Android

#### JVM unit tests on state (ViewModel, `StateFlow`)

- **How it runs.** `./gradlew :app:testDebugUnitTest` on plain JUnit. Google's guidance
  is to use Robolectric "only … as a last resort" for unit tests, and to keep logic
  testable without Android
  ([Android: Robolectric strategies](https://developer.android.com/training/testing/local-tests/robolectric)).
  The repo's Room-backed tests are a legitimate Robolectric use: they need real SQLite.
- **Speed.** Fastest of all: JVM, no device.
- **Determinism.** High.
- **CI.** Runs on Linux runners.
- **Readable by an agent.** JUnit XML plus HTML under `build/`, and plain-text assertion
  messages.
- **Measured on this repo.** See [Measured here](#measured-here).

#### Compose UI tests: Robolectric (local) vs instrumented

- **The API.** `createComposeRule()` / `createAndroidComposeRule<…>()`, then
  `setContent { … }`, `onNodeWithText(…).performClick()` and `assertIsDisplayed()`
  ([Android: Test your Compose layout](https://developer.android.com/develop/ui/compose/testing)).
- **Synchronization is the key property for agents.** "Compose tests are synchronized
  by default … waiting until the UI tree is idle." The app is "advanced in time using a
  virtual clock", so tests "don't run in real time." `mainClock.autoAdvance = false` and
  `advanceTimeBy()` let a test step through animations frame by frame
  ([Android: Synchronize your tests](https://developer.android.com/develop/ui/compose/testing/synchronization)).
  This is the opposite of the WebView situation: no sleeps, no timeouts racing a
  transition.
- **Robolectric or device?** "Any UI test present in the `test` source set runs with
  Robolectric", and behaviour tests such as "a Compose test verif[ying] that the UI has
  changed after clicking a button" have enough fidelity there. Device tests remain for
  system UI (edge-to-edge, picture-in-picture) and unsupported features like
  `WebView` (Robolectric doc above).
  - **Recommended default:** Robolectric. It needs no emulator and runs on Linux CI.
  - **Instrumented tests** (`src/androidTest`, `connectedDebugAndroidTest`) are for the
    few cases that need a real device.
- **Readable by an agent.** `composeTestRule.onRoot().printToLog()` prints the semantics
  tree (node, bounds, `Text = '…'`, `OnClick`) as text
  ([Android: Debug tests](https://developer.android.com/develop/ui/compose/testing/debug)).
  `printToString()` is the same thing as a string, ready for an assertion message or a
  text snapshot.

#### Roborazzi (Robolectric Native Graphics), latest 1.77.0

- **What it is.** JVM screenshot tests under Robolectric 4.10+ with
  `@GraphicsMode(GraphicsMode.Mode.NATIVE)`. `captureRoboImage()` works on Compose nodes,
  Views or composable lambdas ([takahirom/roborazzi](https://github.com/takahirom/roborazzi)).
  It fits the repo's existing Robolectric 4.16 setup.
- **Tasks.**
  - `recordRoborazziDebug` records references.
  - `compareRoborazziDebug` writes `*_compare.png` plus a JSON diff under
    `build/test-results/roborazzi`.
  - `verifyRoborazziDebug` fails on any difference.
  - An HTML report lands at `build/reports/roborazzi/index.html`.
- **Generated tests.** `generateComposePreviewRobolectricTests` (experimental)
  auto-generates tests from `@Preview` functions.
- **Agent-relevant extras.** A **UI tree dump** writes a `*.uitree.json` sidecar with
  Compose semantics. It is informational and never fails verification. That gives a
  text view of what was rendered. Optional AI image-assertion modules also exist
  (`roborazzi-ai-gemini` / `-openai`).
- **Fidelity.** Google notes Robolectric screenshots have "lower" fidelity, and suggests
  them "when the pixel accuracy is not critical": themes, font scales, states. That is
  fine for regression gating, as long as references are recorded on the same JDK and
  Robolectric version used in CI.

#### Paparazzi (Cash App), latest 2.0.0-alpha05.1

- **What it is.** It renders "without a physical device or emulator", for Views and
  `paparazzi.snapshot { Composable() }`.
- **Tasks.** `recordPaparazziDebug` writes to `src/test/snapshots`. `verifyPaparazziDebug`
  writes failure diffs to `build/paparazzi/failures`
  ([cashapp/paparazzi](https://github.com/cashapp/paparazzi)).
- **Version risk.** It ships its own LayoutLib (v16.2.3 in the latest release; it moved
  to compileSdk 36 in alpha02, per
  [releases](https://github.com/cashapp/paparazzi/releases)). Velo compiles against SDK
  37 for material3 1.5.0-alpha, so expect to wait on Paparazzi for new SDK levels.
- **A second renderer.** It runs in the same `test` source set as the existing
  Robolectric tests, but renders with its own LayoutLib, not Robolectric. Adopting it
  would put a second rendering stack in the module.
- **Verdict.** Roborazzi is the better fit here because Robolectric is already set up.

#### Compose Preview Screenshot Testing (Google)

- **Status.** The standalone `com.android.compose.screenshot` plugin "is no longer
  maintained". Google now recommends **AGP test suites** (AGP 9.5.0-alpha03+, engine
  `0.0.1-alpha16`). The feature is marked **Experimental**: "APIs and DSL syntax are
  subject to change"
  ([Android: Compose screenshot testing with test suites](https://developer.android.com/studio/preview/compose-screenshot-testing-with-testsuites)).
- **How it works.**
  - Mark previews with `@PreviewTest` in a `src/screenshotTest` source set.
  - `./gradlew update{Suite}{Target}{Variant}TestSuite` records references.
  - `./gradlew test{Suite}{Target}{Variant}TestSuite` validates them.
  - The HTML report flags `Reference Image Missing`, `Image Size Mismatch` or
    `Pixel Mismatch`.
  - It renders host-side with Layoutlib, no device.
- **Verdict.** It is the most "official" option, but alpha and moving (legacy plugin →
  test suites within a year). Roborazzi is the steadier choice today. Re-evaluate when
  test-suite screenshots go stable.

#### `android studio render-compose-preview`: the agent's eyes, not a gate

- **What it is.** The Android CLI renders a `@Preview` "using Android Studio's layout
  rendering engine". `--print-semantics` prints the semantics tree "in JSON format so AI
  agents can inspect interactive nodes, text, and bounds"
  ([Android CLI](https://developer.android.com/tools/agents/android-cli/commands/studio_render-compose-preview)).
- **Why not a gate.** It connects to a running Android Studio (`--pid`, `--project`),
  so like Xcode's `RenderPreview` it is a development aid, not a CI gate. Unlike Xcode's,
  it gives the agent text as well as pixels.

### Maestro on native views vs WebView content

- **Targeting native views.** Maestro reads the platform accessibility layer.
  - On SwiftUI it recommends `.accessibilityIdentifier()`, targeted with `id:`, as "the
    most resilient way". It warns that some styles (`WheelPickerStyle`) don't return a
    full hierarchy and that Toggles merge text and switch into one element
    ([Maestro: SwiftUI](https://docs.maestro.dev/get-started/supported-platform/ios/swiftui.md)).
  - On Compose it uses semantics (text, `contentDescription`, resource IDs)
    ([Maestro: Jetpack Compose](https://docs.maestro.dev/get-started/supported-platform/android/jetpack.md)).
- **What changes for us.** WebView content is reachable today: CLAUDE.md notes
  `maestro hierarchy` exposes it. But the repo's flows show the cost: transition races,
  30 s waits, and platform-specific casing of CSS-transformed text. Native screens give
  each element a stable identifier and no WebView load to wait for. That removes most
  of those workarounds. iOS presentation quirks remain, for example the sheet over a
  full-screen modal invisible to the driver.
- **Where Maestro still sits.** It is the slowest layer: device boot, app install, a
  live Rails server. Maestro's own retry tolerance makes it a weaker signal for timing
  bugs. Keep it as the pre-PR end-to-end guard and PR-screenshot source, not the inner
  loop.

### CI friendliness

- **Android.** JVM layers (unit, Compose-on-Robolectric, Roborazzi) run on
  `ubuntu-latest` with no emulator. Maestro on Android needs an emulator. GitHub's
  Ubuntu runners support hardware-accelerated emulators once KVM is enabled, and are
  "2–3 times faster" than macOS runners
  ([ReactiveCircus/android-emulator-runner](https://github.com/ReactiveCircus/android-emulator-runner)).
- **iOS.** Every layer needs macOS plus a simulator, so a macOS runner with the Xcode and
  simulator runtime the snapshots were recorded on.
- **What's missing.** Velo has no native CI job yet (`ci.yml`). That decision is the
  map's "CI for native tests" open item. These findings feed it but don't decide it.

## Comparison

| Technique | Device? | Speed | Determinism | CI | Agent reads result as |
|---|---|---|---|---|---|
| Hotwire: Rails/Capybara tests | No | Fast | High, but blind to native nav | Linux | Text, but covers the wrong layer |
| Hotwire: Maestro on WebView | Sim/emulator + Rails | Slow | Low–medium (transition races, timeouts) | Hard | Pass/fail + hierarchy JSON |
| iOS: Swift Testing on models | Simulator (app-hosted); none if moved to a macOS SwiftPM package | Fast tests, about 48 s overhead | High if hostless. Velo's hosted suite: 1/5 green | macOS | Text with captured values |
| iOS: swift-snapshot-testing | Pinned simulator | Fast after boot | High if simulator/OS/Xcode pinned | macOS | Pass/fail text + PNG in `.xcresult`; `.dump` as text diff |
| iOS: preview via Xcode MCP | Xcode GUI open | Fast | n/a (no verdict) | No | PNG |
| iOS: XCUITest | Simulator | Slow | Medium | macOS | Text + screenshots |
| Android: JUnit on ViewModel | No | Fastest | High | Linux | Text |
| Android: Compose test, Robolectric | No | Fast | High (virtual clock, idle sync) | Linux | Text + semantics tree |
| Android: Compose test, instrumented | Emulator | Slow | Medium–high | Linux + KVM | Text |
| Android: Roborazzi | No | Fast | High given pinned JDK/Robolectric | Linux | Pass/fail + `_compare.png` + JSON + `uitree.json` |
| Android: Paparazzi | No | Fast | High | Linux | Pass/fail + diff PNG (lags new SDKs) |
| Android: Compose Preview Screenshot | No | Fast | High | Linux | HTML report with mismatch category (experimental) |
| Android: `render-compose-preview` | Studio open | Fast | n/a (no verdict) | No | PNG + semantics JSON |
| Maestro on native views | Sim/emulator (+ Rails) | Slow | Medium (better than WebView) | Hard | Pass/fail + hierarchy JSON |

## Measured here

Run on the maintainer's Mac on 2026-11-02: Xcode 27.1, iPhone 17 Pro Max simulator
(iOS 26.0 runtime), Robolectric 4.16.

### Android: `./gradlew :app:testDebugUnitTest`

- **Results.** 53 tests in 6 classes. **Green on every run.**
- **Timings.**
  - First run in a fresh worktree, including compile: 42 s wall.
  - Warm `--rerun`: 10 s wall.
  - Test time: pure-JVM classes take milliseconds. The first Robolectric class pays about
    6.7 s of sandbox start-up (`UnsentRecordingsTest`).

### iOS: `xcodebuild test -only-testing VeloTests`

- **Timings.** Cold, including package resolution and build: 86 s wall. Warm: about 48 s
  wall, most of it build, install and app launch. The tests themselves run in under
  0.1 s.
- **Results.** **Not deterministic: 1 green out of 5 runs**, including 2 runs with
  `-parallel-testing-enabled NO`. The failing tests changed between runs:
  - `UnsentRecordingsTests.derivesTotalsForSessionsWithoutThem` / `deleteCascades`
    failed in one run.
  - `RecordingHandoffTests` ("a handoff rebuilt from a stored session…",
    `RecordingHandoffTests.swift:79`) failed in another.
  - The recurring signature is a Core Data exception that kills the test host:
    `-[__NSCFSet addObject:]: attempt to insert nil`, raised "during Core Data change
    processing … within an observer of NSManagedObjectContextObjectsDidChangeNotification".
- **Why the host app matters.** The log also shows the **host app booting the Hotwire
  shell and trying to load `localhost:3000`** while the unit tests run. App-hosted unit
  tests run inside the whole app, including its WebView start-up and Core Data
  observers. That breaks the isolation the bar depends on.
- **Not diagnosed here.** The root cause is outside this ticket's scope and worth its own
  bug. It is direct evidence for two recommendations:
  - On iOS, keep logic tests **out of the app host**: a Swift package or a hostless
    test bundle with injected stores.
  - Gate on N repeated runs (`-test-iterations`) before trusting a new suite.

## Open points for the map

- **Pinning.** Pin the iOS simulator model, runtime and Xcode version for snapshots, and
  the JDK/Robolectric version for Roborazzi. Record references in the same environment
  that verifies them.
- **iOS speed.** A macOS-buildable Swift package for view models and API models would
  give iOS a simulator-free `swift test` loop like Android's JVM loop. This is an
  architecture choice for the navigation and API tickets.
- **Agent-readable failures.** Add text output beside every image snapshot:
  swift-snapshot-testing `.dump` of the view model state, and Roborazzi's
  `uitree.json` / `printToString()`. Then the agent can usually diagnose a failure
  without opening a PNG.
- **Wrapper tasks.** Add `mise run test` per platform: `xcodebuild test` on a fixed
  destination, and `./gradlew :app:testDebugUnitTest verifyRoborazziDebug`. The agent
  then has one command per platform.
