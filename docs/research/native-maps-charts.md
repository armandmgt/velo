# Native maps and charts in the agent loop

Research for [Native maps and charts in the agent loop (#18)](https://github.com/armandmgt/velo/issues/18),
part of the map [#4](https://github.com/armandmgt/velo/issues/4). It builds on
[Agent test loop for SwiftUI and Compose (#7)](https://github.com/armandmgt/velo/issues/7)
and [ADR 0006](../adr/0006-core-screens-are-native.md).
Researched 2026-11-05.

**The question.** Which libraries draw the store v1 maps and charts natively, and how
does each one get a deterministic CLI pass/fail in the agent loop?

Each claim is marked **[fact]** (read in a primary source, or measured here) or
**[inference]** (my reasoning from facts; verify before relying on it).

## TL;DR

- **Maps: keep MapLibre Native on both platforms, used directly.** Both apps already
  ship it and already load the MapTiler style from `/configurations`. It draws a
  MultiLineString, so tracks with hidden portions need no new work. It has the pieces
  the planner needs: feature queries, long press, screen↔coordinate conversion.
  Wrap the raw SDK (`MLNMapView` in `UIViewRepresentable`, `MapView` in `AndroidView`).
  Don't adopt the SwiftUI/Compose wrapper libraries yet: both are pre-1.0.
- **Charts: Swift Charts on iOS, Vico on Android.** Both draw lines, filled areas and
  bars, and both support selection for the chart→map scrub. The zone bars are plain
  views and need no chart library. **Downsample on the server** (≈1,000 points per
  series): a 4-hour ride has about 14,400 per-second points, and iOS 17 has no
  vectorized line plot.
- **Testing: the map is the one thing no fast check can render.** Under Robolectric,
  MapLibre Android throws `UnsatisfiedLinkError` (measured). So put the map behind a
  thin seam. Assert on a plain **map model** (GeoJSON, camera bounds, waypoints) in
  unit tests, and render a placeholder in Roborazzi/snapshot tests. On iOS, a real map
  render can be snapshotted through `MLNMapSnapshotter` on the pinned simulator.
  Android's real-map check needs an emulator. Charts snapshot normally on both.
- **Planner handles: draw them as app views over the map, not SDK annotations.** Then
  Compose UI tests, SwiftUI tests and Maestro can see and drag them. iOS SDK
  annotations need a press-and-hold before a drag, and Maestro can't do that yet.
- **Version bumps to plan:** MapLibre iOS 6.27 → 7.0, MapLibre Android 11.8 → 13.x
  (Vulkan becomes the default backend), and Kotlin 2.2.21 → 2.4 for Vico 3.3. The
  build file's reason for holding Kotlin back (KSP) no longer holds.

## What the repo has today

- **iOS** uses MapLibre through SPM from `maplibre-gl-native-distribution`,
  `from: "6.0.0"`, with deployment target iOS 17.0 (`native/ios/project.yml`). The
  local `Package.resolved` pins **6.27.0**. [fact]
- **Android** uses `org.maplibre.gl:android-sdk:11.8.0` with minSdk 30, compileSdk 37,
  Kotlin 2.2.21, Compose BOM 2026.06.00 and Robolectric 4.16
  (`native/android/app/build.gradle.kts`, `native/android/build.gradle.kts`). [fact]
- Both recording maps read `map_style_url` and `map_accent` from the path
  configuration `settings` (`ConfigurationsController.map_settings`), then draw the
  trace as a white casing under an accent line. iOS: `RecordingMapView.swift` (UIKit
  `MLNMapView`). Android: `RecordingMap.kt` (`MapView` in `AndroidView`, polling for
  the style URL because the remote config arrives late). [fact]
- So **"can it load the MapTiler style URL?" is already answered yes** on both
  platforms, in production code. [fact]
- `map_style_url` embeds the MapTiler key in an unauthenticated endpoint. The
  controller already notes this. Native screens don't change it. [fact]

## Maps

### Releases

| | Current in app | Latest stable | Notes |
|---|---|---|---|
| MapLibre iOS | 6.27.0 | [7.0.0](https://github.com/maplibre/maplibre-native/releases/tag/ios-v7.0.0) (2026-10-28) | Min iOS 15.5. Renames `Mapbox.h` → `MapLibre.h`; Swift unchanged. Adds rendered-feature introspection. [fact] |
| MapLibre Android | 11.8.0 | [13.7.1](https://github.com/maplibre/maplibre-native/releases/tag/android-v13.7.1) (2026-10-15) | 13.0 made **Vulkan** the default backend of `android-sdk`; OpenGL ES moved to `android-sdk-opengl` ([CHANGELOG](https://github.com/maplibre/maplibre-native/blob/main/platform/android/CHANGELOG.md)). 12.0 raised minSdk to 23. Built with Kotlin 2.3.20. [fact] |
| [maplibre/swiftui-dsl](https://github.com/maplibre/swiftui-dsl) | — | 0.26.1 | Pre-1.0; "robust for the subset of the MapLibre iOS API that it supports". [fact] |
| [maplibre/maplibre-compose](https://github.com/maplibre/maplibre-compose) | — | 0.20.0 | Android/iOS **Beta**: "minor releases can contain breaking changes". [fact] |

The SPM constraint `from: "6.0.0"` stops below 7.0, so moving to 7.0 is a
`project.yml` edit. [fact]

### Activity track with hidden portions

- The server already cuts hidden portions. For a non-owner, `MapVisibility#path_geojson`
  returns a `MultiLineString` with one line per visible run. The web just draws it
  (`map_controller.js`). [fact]
- iOS: `MLNShape(data:encoding:)` parses any GeoJSON geometry, and
  `MLNMultiPolyline` is the MultiLineString type
  ([MLNPolyline.h](https://github.com/maplibre/maplibre-native/blob/main/platform/darwin/src/MLNPolyline.h),
  [MLNShape.h](https://github.com/maplibre/maplibre-native/blob/main/platform/darwin/src/MLNShape.h)). [fact]
- Android: `GeoJsonSource` takes any GeoJSON. `org.maplibre.geojson.MultiLineString`
  is a pure-Java type that works on the JVM (measured below). [fact]
- So the native client needs **no privacy logic**: draw the geometry the API returns.
  The rule from `MapVisibility` ("hidden coordinates never leave the server") must
  hold for the JSON API too. [inference]
- The chart→map scrub needs one coordinate per chart point, `nil` where hidden
  (`MapVisibility#chart_data`). If the server downsamples, it must downsample the
  `coordinates` array with the same indices, keeping `nil`s. [inference]
- Native viewers are usually the owner (they see their own activities), so they get
  the full track. The cut matters when a native screen shows someone else's
  activity. [inference]

### Route planner interactions

What the web does today (`route_planner_controller.js`) [fact]:

- tap on the map adds a waypoint at the end;
- tap on the route line (8 px tolerance, via `queryRenderedFeatures` on the line and
  casing layers) **inserts** a waypoint, at the slot found by nearest route index;
- waypoint markers drag (MapLibre GL JS `Marker({ draggable: true })`);
- right-click or double-click on a marker removes it;
- undo/redo history; a debounced `POST` to the preview endpoint returns geometry,
  distance, elevation gain and elevation samples.

The web has **no** "drag the line to insert" and **no** long press to add. Both
would be new on the phone; the prototype ticket should decide whether they are
needed. [fact]

What the SDKs offer:

| Need | iOS (MapLibre 7.0) | Android (MapLibre 13.x) |
|---|---|---|
| Screen ↔ coordinate | `convert(_:toCoordinateFrom:)` / `convert(_:toPointTo:)` ([MLNMapView.h](https://github.com/maplibre/maplibre-native/blob/main/platform/ios/src/MLNMapView.h)) [fact] | `map.projection.fromScreenLocation` / `toScreenLocation` [fact] |
| Hit-test the route line | `visibleFeatures(in:styleLayerIdentifiers:)` [fact] | `queryRenderedFeatures(RectF, layerIds)` [fact] |
| Long press | add a `UILongPressGestureRecognizer` to the map view [inference: standard UIKit] | `addOnMapLongClickListener` [fact] |
| Draggable handle (SDK way) | `MLNAnnotationView.isDraggable`: the user must **press and hold, then drag** ([MLNAnnotationView.h](https://github.com/maplibre/maplibre-native/blob/main/platform/ios/src/MLNAnnotationView.h)) [fact] | Annotation plugin `org.maplibre.gl:android-plugin-annotation:4.0.0`, `SymbolManager` with draggable symbols ([v4.0.0](https://github.com/maplibre/maplibre-plugins-android/releases/tag/v4.0.0)). Its drag controller queried features on every pan until a fix in [#86](https://github.com/maplibre/maplibre-plugins-android/pull/86) ([#83](https://github.com/maplibre/maplibre-plugins-android/issues/83)). [fact] |

**Recommendation for handles: app-drawn overlays on both platforms.** Draw each
waypoint handle as a SwiftUI/Compose view above the map. Place it with the map's
`coordinate → screen` conversion, and move it again on every camera change. Drag it
with the platform's own drag gesture, and convert to a coordinate on release.
[inference]

- **Testable.** The handles are ordinary views. Compose UI tests
  (`performTouchInput`) and Roborazzi can drive and capture them with a fake
  projection, with no GL. Maestro sees them by `testTag`/`accessibilityIdentifier`.
  [inference]
- **Same on both platforms.** It avoids the iOS press-and-hold rule and the Android
  plugin's history. [inference]
- **Commit the drag once, on release.** maplibre-compose's spike found that rewriting
  a GeoJSON source on every pointer event leaves the handle trailing, and that handle
  positions must be computed in layout (`Modifier.offset { }`), not in composition
  ([maplibre-compose#953](https://github.com/maplibre/maplibre-compose/issues/953)). [fact]
- **Risk:** handles may lag one frame behind the GL map during a pan or zoom. Check
  this on a real phone in the planner prototype. Fallback: SDK annotations
  (iOS `MLNAnnotationView`, Android annotation plugin). [inference]
- **Hit-test the line in the model, not with GL queries.** Project the route to
  screen points and measure the tap's distance to each segment (the web's 8 px).
  This is pure geometry and runs in a unit test. `visibleFeatures` /
  `queryRenderedFeatures` stay as a cross-check on device. [inference]

The waypoint list (add, insert slot, move, remove, undo/redo, the preview request
body) is pure logic. Port `route_planner_controller.js` into a Swift/Kotlin model
with unit tests. It is the planner's main thing to assert on. [inference]

## Charts

What activity detail shows on the web [fact]:

- **One line chart with a series picker:** speed (km/h), cadence, power, heart rate
  (`ActivityCharts#chart_data`, `activity_charts_controller.js`). The x-axis is
  elapsed time. When a max HR is set, the HR line is tinted **per segment by zone**.
  Hover moves a marker on the map.
- **Elevation profile:** a filled line, on time or distance (`_elevation_profile.html.erb`).
- **HR and power zones:** a stacked horizontal bar plus a table
  (`_heart_rate_zones.html.erb`, `_power_zones.html.erb`). The server computes the
  percentages. These are plain views, not charts.
- **All points are sent.** One point per data point, with no downsampling.

### iOS: Swift Charts

- `LineMark` and `AreaMark` cover the series and the elevation profile. The bars can
  be `BarMark` or plain shapes. [fact: Swift Charts API]
- **Selection:** `chartXSelection(value:)` is **iOS 17.0+**, which fits the
  deployment target. It drives the map scrub
  ([docs](https://developer.apple.com/documentation/swiftui/view/chartxselection(value:))). [fact]
- **Large data:** Apple says to "use vectorized plots for larger datasets", and to use
  marks for fewer points with per-element styling
  ([WWDC24 10155](https://developer.apple.com/videos/play/wwdc2024/10155/)).
  `LinePlot` is **iOS 18.0+** ([docs](https://developer.apple.com/documentation/charts/lineplot)). [fact]
  - With iOS 17 and per-second data, either downsample or raise the target to 18.
    Downsampling is needed anyway (see below), so stay on 17 with `LineMark`.
    [inference]
- **Zone-tinted HR line:** no direct API. Options: a vertical `LinearGradient` with
  hard stops at the zone bpm on a fixed y-domain, or one series per zone run.
  Prototype it. [inference]
- **Accessibility:** Swift Charts builds accessibility elements for its marks, and
  `accessibilityChartDescriptor(_:)` (iOS 15+) can describe a whole chart
  ([docs](https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:))). [fact]
  With 1,000 marks, give the chart one summary element instead, so Maestro's
  hierarchy stays small. [inference]

### Android: Vico

- [Vico](https://github.com/patrykandpatrick/vico) 3.3.1 is the latest stable
  (2026-08-28). It is Compose Multiplatform, active (3,200 stars, pushed 2026-10-30).
  [fact]
- `LineCartesianLayer` has `LineFill.single(Fill)` and `LineFill.double(top, bottom, splitY)`,
  plus `AreaFill` for the elevation profile. A `Fill` can carry a Compose `Brush`
  ([LineCartesianLayer.kt](https://github.com/patrykandpatrick/vico/blob/master/vico/compose/src/commonMain/kotlin/com/patrykandpatrick/vico/compose/cartesian/layer/LineCartesianLayer.kt)).
  [fact] A vertical gradient brush with hard stops gives the zone tint, as on iOS.
  [inference]
- Markers (`CartesianMarkerController`, `CartesianMarkerVisibilityListener`) give the
  scrub→map hook. [fact: files exist in the Compose module]
- **Performance:** a 5,000-point single line scrolls fine; slowness was reported with
  many series ([#1019](https://github.com/patrykandpatrick/vico/issues/1019),
  [#1025](https://github.com/patrykandpatrick/vico/issues/1025)). We draw one series
  at a time. [fact]
- **Renders off-device.** Vico's own sample has host-side screenshot tests with
  reference images (`sample/android/src/screenshotTest`). [fact] So Roborazzi under
  Robolectric should capture it too, because it draws on a Compose `Canvas`.
  [inference: confirm in the first chart test]
- **Kotlin version gate.** Vico 3.3.1 is built with Kotlin **2.4.10**, and 3.0.0 with
  2.3.10. [fact] Kotlin guarantees only that a compiler is "mostly" forward-compatible
  "with the next language release, but not later ones"
  ([Kotlin evolution](https://kotlinlang.org/docs/kotlin-evolution-principles.html)).
  [fact] So the app's Kotlin 2.2.21 can't safely use Vico 3.3. Bump Kotlin, or pin
  Vico 3.0.x. [inference]
  - The build file holds Kotlin at 2.2.21 because "KSP has no 2.3/2.4 build yet". That
    is stale: since KSP 2.3.0, "KSP version is no longer tied to the Kotlin compiler
    version" ([KSP 2.3.0](https://github.com/google/ksp/releases/tag/2.3.0)). The
    app already uses KSP 2.3.2. [fact]
- Alternatives: hand-drawn charts on a Compose `Canvas` are also viable for four
  simple charts, and render under Roborazzi. Vico saves axes, markers and scrolling.
  [inference]

### Downsampling

- Per-second data gives about 3,600 points per hour, so 14,400 for a 4-hour ride, for
  each of 4 series plus elevation and coordinates. [fact: `ActivityDataPoint` is per
  second, `chart_data` sends every point]
- A phone chart is about 1,000–1,200 px wide, so more points than that add no detail.
  [inference]
- **Downsample on the server, in the JSON API**, with a shape-keeping method such as
  LTTB, to about 1,000 points per series. Keep the x value and the coordinate of each
  kept point. One Ruby implementation then serves both platforms, is tested with
  `bin/rails test`, and shrinks the payload. [inference]
- Run it after the visibility cut, so a hidden coordinate stays `nil`. [inference]

## Testing in the agent loop

### Measured here (2026-11-05)

A throwaway Robolectric test in `native/android/app/src/test` (Robolectric 4.16,
`@GraphicsMode(NATIVE)`, MapLibre 11.8.0), deleted afterwards. [fact]

| Call | Result under Robolectric |
|---|---|
| `MapLibre.getInstance(context)` | `UnsatisfiedLinkError: NativeConnectivityListener.initialize()` |
| `MapView(context)` | `UnsatisfiedLinkError: MapRenderer.nativeInitialize(...)` |
| `GeoJsonSource("route")` | `UnsatisfiedLinkError: GeoJsonSource.initialize(...)` |
| `org.maplibre.geojson.MultiLineString.fromLngLats(...).toJson()` | works |

Why: `libmaplibre.so` is built for Android only. `LibraryLoader` swallows the load
failure when `PlatformUtils.isTest()` sees JUnit or Robolectric, but every later
native call fails
([LibraryLoader.java](https://github.com/maplibre/maplibre-native/blob/main/platform/android/MapLibreAndroid/src/main/java/org/maplibre/android/LibraryLoader.java),
[PlatformUtils.java](https://github.com/maplibre/maplibre-native/blob/main/platform/android/MapLibreAndroid/src/main/java/org/maplibre/android/utils/PlatformUtils.java)). [fact]
Robolectric's `GLSurfaceView` is a shadow, and there is no GPU in JVM tests
([ShadowGLSurfaceView](https://robolectric.org/javadoc/latest/org/robolectric/shadows/ShadowGLSurfaceView.html)). [fact]
**So no Robolectric or Roborazzi test can render a MapLibre map.** [fact]

### The seam (both platforms)

[inference, the design that follows from the facts above]

1. **A map model** holds everything we would otherwise check in pixels: the
   track GeoJSON (LineString or MultiLineString, segment count), the camera bounds
   and padding, the scrub marker coordinate, and for the planner the waypoints, the
   routed line and the insert slot. It builds GeoJSON with pure types:
   `org.maplibre.geojson` on Android (works on the JVM), Codable structs on iOS.
2. **A thin map view** applies the model to MapLibre: style URL, sources, layers
   (casing under line), camera. It has no logic of its own.
3. **A map slot.** Screens take the map view as a parameter or a
   `CompositionLocal`/`Environment` value. Tests pass a placeholder that draws a
   flat box with the model's summary as text. Roborazzi and swift-snapshot-testing
   then capture the whole screen without GL.
4. **A projection protocol** (`coordinate ↔ screen point`). It is real MapLibre in the
   app and a fixed linear fake in tests, so handle placement, drags and line hit-tests
   run in Compose UI tests and Swift tests.

### Per-platform checks

| What | iOS (pinned simulator) | Android (JVM unless noted) |
|---|---|---|
| Map model, planner model, chart series, downsampled data | Swift Testing, hostless | JUnit, plain or Robolectric |
| Screen with map placeholder, handles, charts | swift-snapshot-testing `.image` + `.dump` | Roborazzi + `printToString()` |
| Handle drag, tap-to-insert, long press | SwiftUI tests with the fake projection | Compose UI test `performTouchInput` with the fake projection |
| **Real map pixels** | `MLNMapSnapshotter` → `UIImage` → `assertSnapshot(of: image, as: .image)`, with a **local fixture style** (`file://`, no network) and our layers added in `mapSnapshotter(_:didFinishLoadingStyle:)` | **Needs an emulator.** Instrumented test with `featureInfoEnabled` + `getRenderedFeatureCount()` (13.7+) |
| End to end | Maestro | Maestro |

Notes on the real-map row:

- **iOS snapshotting the live `MLNMapView` won't work by default.**
  swift-snapshot-testing renders with `layer.render(in:)`, or with
  `drawHierarchyInKeyWindow`, which "requires tests to be run in a host application"
  ([View.swift](https://github.com/pointfreeco/swift-snapshot-testing/blob/main/Sources/SnapshotTesting/Common/View.swift)).
  MapLibre iOS renders with Metal since 6.0
  ([ios-v6.0.0](https://github.com/maplibre/maplibre-native/releases/tag/ios-v6.0.0)),
  and the hosted test bundle is the flaky one (see #7). SwiftUI's `ImageRenderer`
  shows "a placeholder image" for UIKit views
  ([docs](https://developer.apple.com/documentation/swiftui/imagerenderer)). [fact]
  The likely result is a blank map in the snapshot. [inference]
- **`MLNMapSnapshotter` is the workaround.** It renders offscreen to an image. Its
  style can be changed in `mapSnapshotter(_:didFinishLoadingStyle:)`
  ([MLNMapSnapshotter.h](https://github.com/maplibre/maplibre-native/blob/main/platform/darwin/src/MLNMapSnapshotter.h)).
  Metal support landed in 2024 ([#1862](https://github.com/maplibre/maplibre-native/issues/1862)),
  and MapLibre runs its own snapshotter tests on the simulator
  (`platform/ios/Integration_Tests/Snapshotter Tests`). [fact] Share one
  "add track layers to style" function between the live view and the snapshotter,
  and the snapshot tests the real layer styling. [inference] **Not measured here:**
  confirm it runs in a hostless bundle and gives the same pixels on every run.
- **Use a fixture style, never MapTiler, in tests.** `styleURL` may be "a path to a
  local file" ([MLNMapView.h](https://github.com/maplibre/maplibre-native/blob/main/platform/ios/src/MLNMapView.h));
  `styleJSON` also exists. [fact] Tiles over the network make snapshots
  non-deterministic and spend the key. [inference]
- **Rendered-feature introspection** (iOS 7.0, Android 13.7) is "intended primarily
  to assist with testing of host applications": it reports which features each layer
  drew and where ([PR #4460](https://github.com/maplibre/maplibre-native/pull/4460)).
  [fact] It gives a text assertion ("the route layer drew 2 features, both on screen")
  instead of a pixel diff. It still needs a live map, so a simulator on iOS and an
  emulator on Android. [inference]
- **Android 13.x defaults to Vulkan.** If emulator rendering is unreliable, use the
  `android-sdk-opengl` artifact. [fact: artifact exists; inference: may be needed]

### Maestro

- **iOS map:** MapLibre exposes annotations and basemap places and roads as
  accessibility elements (`MLNMapAccessibilityElement.h`: annotation, feature, place,
  road, map proxy). [fact] The basemap can bloat the hierarchy. [inference]
- **Android map:** I found no accessibility node provider in MapLibre Android, so the
  map is likely one opaque node. [inference: code search found none]
- **What to do:** give the map container an identifier and a short summary label from
  the model ("2 segments", "4 waypoints"). Give handles their own identifiers
  (`waypoint-1`…). Maestro then asserts text, not pixels. [inference]
- **Gestures:** Maestro has `tapOn` (point), `longPressOn`, and `swipe` with
  `start`/`end`/`duration` ([swipe](https://docs.maestro.dev/api-reference/commands/swipe)).
  [fact] A `drag` command exists only as an **open PR**
  ([#2978](https://github.com/mobile-dev-inc/maestro/pull/2978); request
  [#1203](https://github.com/mobile-dev-inc/maestro/issues/1203)). [fact] A swipe
  from a handle drags an app-drawn handle. It can't do the hold-then-drag that iOS
  `MLNAnnotationView` needs. [inference] This supports the overlay design.
- The local Maestro is 2.6.0; the latest is CLI 2.12.1 (2026-11-02). [fact]
- **Charts:** expose one summary element per chart (series, min/max/avg), not
  1,000 mark elements. [inference]

## Recommendation per platform

### iOS

- **Map:** MapLibre iOS **7.0**, raw `MLNMapView` in `UIViewRepresentable` (extends the
  existing `RecordingMapView` pattern). Skip swiftui-dsl for now (pre-1.0, a subset of
  the API).
- **Planner:** SwiftUI overlay handles + a projection protocol; long press via
  `UILongPressGestureRecognizer`; line hit-test in the model.
- **Charts:** Swift Charts `LineMark`/`AreaMark` on iOS 17, fed downsampled series;
  `chartXSelection` for the scrub; zone bars as plain shapes.
- **Checks:** Swift Testing on the models (hostless); swift-snapshot-testing for
  screens with a map placeholder and for charts; `MLNMapSnapshotter` + fixture style
  for real map pixels.
- **Trade-off:** every check needs the pinned simulator (already true per #7). The
  real-map snapshot is the least proven piece.

### Android

- **Map:** MapLibre Android **13.x**, raw `MapView` in `AndroidView` (extends
  `RecordingMap.kt`). Skip maplibre-compose for now (Beta, breaking minor releases).
- **Planner:** Compose overlay handles + a projection interface;
  `addOnMapLongClickListener`; line hit-test in the model.
- **Charts:** Vico 3.3 after a Kotlin bump (or Vico 3.0.x on Kotlin 2.2), or plain
  Compose `Canvas` if Vico fights us.
- **Checks:** JUnit/Robolectric on the models; Roborazzi for screens with a map
  placeholder and for charts. Real map pixels only on an emulator (instrumented test
  with rendered-feature counts) or via Maestro.
- **Trade-off:** the fast loop stays JVM-only, but it never sees the real map. The
  seam has to be thin enough that "the model is right" means "the map is right".

## Open items for downstream tickets

For **Activity detail sections in the native v1 (#19):**

- The JSON API should return the visibility-cut geometry and server-downsampled chart
  series with aligned coordinates (`nil` where hidden).
- First spike: one `MLNMapSnapshotter` snapshot with a fixture style in a hostless iOS
  bundle, run 5 times. If it isn't deterministic, fall back to rendered-feature counts
  on the simulator.
- First spike: one Vico chart under Roborazzi. Do it together with the Kotlin bump.
- Prototype the zone-tinted HR line on both platforms (gradient with hard stops).

For **Prototype the native route planner on a phone (#21):**

- Check that overlay handles track the map during pan, zoom and fling on a real
  phone. If they lag, fall back to SDK annotations and accept weaker tests.
- Decide whether "drag the line to insert" and "long press to add" are wanted.
  Neither exists on the web.
- Port the waypoint model from `route_planner_controller.js` with tests first.

For the map in general:

- MapLibre iOS 7.0 and Android 13.x upgrades touch the recording screen. Re-run
  its Maestro flows after the bump.
- Kotlin 2.2.21 → 2.4 (KSP no longer blocks it).
- Update Maestro from 2.6.0.
