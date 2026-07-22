package fr.armandmgt.velo.features.record

import android.graphics.Color
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import dev.hotwire.core.config.Hotwire
import kotlinx.coroutines.delay
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

private const val ROUTE_SOURCE = "route"
private const val POSITION_SOURCE = "position"
private const val FALLBACK_ACCENT = "#ee7f2b"

/**
 * The full-bleed live map behind the recording screen (redesign per
 * `Recording.dc.html`).
 *
 * Draws the recorded trace ([routePoints]) as an accent line over a white casing —
 * mirroring the web `map_controller.js` — plus a ringed [position] marker, and
 * eases the camera to follow the latest fix (keeping it above the dock via
 * [bottomPaddingPx]). The marker/trace are fed from our own [RecordingService]
 * fixes, not MapLibre's location engine, so the single GPS owner + While-Using
 * posture are preserved.
 *
 * The basemap style URL + accent come from the server via the path configuration's
 * `settings` ([AndroidMapConfig]) — the same MapTiler style the web uses. On a
 * fresh install Hotwire serves the bundled config first and the remote (keyed)
 * config a moment later, so the style URL is polled until it appears.
 */
@Composable
fun RecordingMap(
    routePoints: List<RoutePoint>,
    position: RoutePoint?,
    bottomPaddingPx: Int,
    modifier: Modifier = Modifier,
) {
    val holder = remember { MapHolder() }
    val accent = remember { AndroidMapConfig.accentColor() }
    var styleUrl by remember { mutableStateOf(AndroidMapConfig.styleUrl()) }
    val mapView = rememberRecordingMapView()

    // The server-delivered style URL may not be in the path config yet on a fresh
    // install (Hotwire loads the bundled asset first, then the remote async), so
    // poll briefly until it appears; the style is then applied reactively below.
    LaunchedEffect(Unit) {
        var waited = 0
        while (styleUrl == null && waited < 10_000) {
            delay(300)
            waited += 300
            styleUrl = AndroidMapConfig.styleUrl()
        }
    }

    AndroidView(factory = { mapView }, modifier = modifier) { view ->
        if (holder.map == null && !holder.requested) {
            holder.requested = true
            view.getMapAsync { map ->
                holder.map = map
                map.uiSettings.isTiltGesturesEnabled = false
                holder.applyStyle(styleUrl, accent, routePoints, position, bottomPaddingPx)
            }
        }
    }

    LaunchedEffect(styleUrl) { holder.applyStyle(styleUrl, accent, routePoints, position, bottomPaddingPx) }
    LaunchedEffect(routePoints) { holder.applyRoute(routePoints) }
    LaunchedEffect(position, bottomPaddingPx) { holder.applyPosition(position, bottomPaddingPx, animate = true) }
}

/** Mutable references to the map + its sources, held across recompositions. */
private class MapHolder {
    var requested = false
    var map: MapLibreMap? = null
    private var routeSource: GeoJsonSource? = null
    private var positionSource: GeoJsonSource? = null
    private var styleApplied = false
    private var centered = false

    /** Load the basemap style (once the URL is known) and (re)add our sources +
     *  layers on top, then draw whatever data already exists. */
    fun applyStyle(
        styleUrl: String?,
        accent: Int,
        route: List<RoutePoint>,
        position: RoutePoint?,
        bottomPaddingPx: Int,
    ) {
        val map = map ?: return
        if (styleApplied || styleUrl == null) return
        styleApplied = true

        map.setStyle(Style.Builder().fromUri(styleUrl)) { style ->
            val routeSource = GeoJsonSource(ROUTE_SOURCE)
            style.addSource(routeSource)
            this.routeSource = routeSource
            style.addLayer(
                LineLayer("route-casing", ROUTE_SOURCE).withProperties(
                    PropertyFactory.lineColor(Color.WHITE),
                    PropertyFactory.lineWidth(8f),
                    PropertyFactory.lineOpacity(0.9f),
                    PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                    PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                ),
            )
            style.addLayer(
                LineLayer("route-line", ROUTE_SOURCE).withProperties(
                    PropertyFactory.lineColor(accent),
                    PropertyFactory.lineWidth(5f),
                    PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                    PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                ),
            )

            val positionSource = GeoJsonSource(POSITION_SOURCE)
            style.addSource(positionSource)
            this.positionSource = positionSource
            style.addLayer(
                CircleLayer("position-halo", POSITION_SOURCE).withProperties(
                    PropertyFactory.circleColor(accent),
                    PropertyFactory.circleRadius(16f),
                    PropertyFactory.circleOpacity(0.18f),
                ),
            )
            style.addLayer(
                CircleLayer("position-dot", POSITION_SOURCE).withProperties(
                    PropertyFactory.circleColor(accent),
                    PropertyFactory.circleRadius(7f),
                    PropertyFactory.circleStrokeColor(Color.WHITE),
                    PropertyFactory.circleStrokeWidth(3f),
                ),
            )

            applyRoute(route)
            applyPosition(position, bottomPaddingPx, animate = false)
        }
    }

    fun applyRoute(points: List<RoutePoint>) {
        val source = routeSource ?: return
        if (points.size >= 2) {
            val line = LineString.fromLngLats(points.map { Point.fromLngLat(it.longitude, it.latitude) })
            source.setGeoJson(Feature.fromGeometry(line))
        } else {
            source.setGeoJson(FeatureCollection.fromFeatures(emptyList()))
        }
    }

    fun applyPosition(position: RoutePoint?, bottomPaddingPx: Int, animate: Boolean) {
        val map = map ?: return
        if (position == null) {
            positionSource?.setGeoJson(FeatureCollection.fromFeatures(emptyList()))
            return
        }
        positionSource?.setGeoJson(Feature.fromGeometry(Point.fromLngLat(position.longitude, position.latitude)))
        map.setPadding(0, 0, 0, bottomPaddingPx)
        val latLng = LatLng(position.latitude, position.longitude)
        val zoom = if (centered) map.cameraPosition.zoom.coerceAtLeast(15.0) else 15.0
        val update = CameraUpdateFactory.newLatLngZoom(latLng, zoom)
        if (animate && centered) map.animateCamera(update) else map.moveCamera(update)
        centered = true
    }
}

/** Reads the map style URL + accent delivered in the path configuration's flat
 *  `settings` keys (see `ConfigurationsController`); same source as iOS. */
private object AndroidMapConfig {
    fun styleUrl(): String? = Hotwire.config.pathConfiguration.settings["map_style_url"] as? String

    fun accentColor(): Int {
        val hex = Hotwire.config.pathConfiguration.settings["map_accent"] as? String ?: FALLBACK_ACCENT
        return runCatching { Color.parseColor(hex) }.getOrDefault(Color.parseColor(FALLBACK_ACCENT))
    }
}

/**
 * A [MapView] wired to the composition's lifecycle. MapLibre is initialised before
 * the view is created; `onCreate`/`onDestroy` bracket the composition while the
 * remaining callbacks follow the host lifecycle (so the map doesn't leak or render
 * black when the app is backgrounded mid-recording).
 */
@Composable
private fun rememberRecordingMapView(): MapView {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val mapView = remember {
        MapLibre.getInstance(context)
        MapView(context)
    }

    DisposableEffect(Unit) {
        mapView.onCreate(null)
        onDispose { mapView.onDestroy() }
    }

    DisposableEffect(lifecycle) {
        // Adding the observer while the host is already RESUMED replays
        // ON_START/ON_RESUME, so onStart/onResume fire exactly once here.
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    return mapView
}
