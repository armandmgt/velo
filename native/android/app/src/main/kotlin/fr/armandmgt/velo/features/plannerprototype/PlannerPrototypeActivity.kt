// PROTOTYPE — throwaway (wayfinder #21). The combination chosen on iOS: app-drawn
// handles, tap the line to insert, and a bottom sheet with detents.
package fr.armandmgt.velo.features.plannerprototype

import android.content.Intent
import android.graphics.Color
import android.graphics.PointF
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import dev.hotwire.core.config.Hotwire
import fr.armandmgt.velo.ui.theme.VeloTheme
import kotlinx.coroutines.launch
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import kotlin.math.hypot
import kotlin.math.roundToInt

class PlannerPrototypeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            VeloTheme {
                PlannerScreen(
                    onClose = { finish() },
                    onSaved = { url -> setResult(RESULT_OK, Intent().putExtra(EXTRA_URL, url)); finish() },
                )
            }
        }
    }

    companion object { const val EXTRA_URL = "url" }
}

/** Map + projection seam: the overlay reads [tick] so handles re-place every camera frame. */
private class MapHolder {
    var map: MapLibreMap? = null
    var routeSource: GeoJsonSource? = null
    var bandSource: GeoJsonSource? = null
    var tick by mutableIntStateOf(0)
    var ready by mutableStateOf(false)

    fun point(c: Coord): PointF? { tick; return map?.projection?.toScreenLocation(LatLng(c.lat, c.lng)) }
    fun coord(p: PointF): Coord? = map?.projection?.fromScreenLocation(p)?.let { Coord(it.longitude, it.latitude) }
}

private const val LINE_TOLERANCE_DP = 18f
private const val HANDLE_RADIUS_DP = 26f

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun PlannerScreen(onClose: () -> Unit, onSaved: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val model = remember { PlannerModel(scope) }
    val holder = remember { MapHolder() }
    val context = LocalContext.current
    val density = LocalDensity.current.density
    var saving by remember { mutableStateOf(false) }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@rememberLauncherForActivityResult
        model.importGpx(bytes, "import.gpx")
    }

    BottomSheetScaffold(
        scaffoldState = rememberBottomSheetScaffoldState(),
        sheetPeekHeight = 130.dp,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        sheetContent = {
            Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Stats(model)
                    Spacer(Modifier.weight(1f))
                    Button(
                        onClick = { saving = true; scope.launch { model.save()?.let(onSaved); saving = false } },
                        enabled = model.waypoints.size >= 2 && !saving,
                        modifier = Modifier.testTag("planner-save"),
                    ) { Text("Enregistrer") }
                }
                OutlinedTextField(model.name, { model.name = it }, label = { Text("Nom de l’itinéraire") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("planner-name"))
                SportPicker(model)
                if (model.elevationSamples.size > 1) ElevationProfile(model.elevationSamples)
                OutlinedButton(onClick = { importer.launch(arrayOf("*/*")) }, modifier = Modifier.testTag("planner-import-gpx")) { Text("Importer un GPX") }
            }
        },
    ) {
        Box(Modifier.fillMaxSize()) {
            PlannerMap(model, holder, density)
            // App-drawn handles over the map.
            model.waypoints.forEachIndexed { i, w ->
                val moving = model.dragPreview?.takeIf { it.movingIndex == i }?.coordinate
                val p = holder.point(moving ?: w) ?: return@forEachIndexed
                val half = (24 * density).roundToInt()
                var dragAt by remember(i) { mutableStateOf(PointF()) }
                Box(
                    Modifier
                        .offset { IntOffset(p.x.roundToInt() - half, p.y.roundToInt() - half) }
                        .size(48.dp)
                        .testTag("planner-waypoint-${i + 1}")
                        .semantics { contentDescription = "Point ${i + 1}" }
                        .pointerInput(i) {
                            detectTapGestures { model.selectedIndex = if (model.selectedIndex == i) null else i }
                        }
                        .pointerInput(i, model.waypoints.size) {
                            detectDragGestures(
                                onDragStart = { dragAt = holder.point(model.waypoints[i]) ?: PointF() },
                                onDrag = { change, amount ->
                                    change.consume()
                                    dragAt = PointF(dragAt.x + amount.x, dragAt.y + amount.y)
                                    holder.coord(dragAt)?.let { model.dragPreview = DragPreview(i, it) }
                                },
                                onDragEnd = {
                                    model.dragPreview = null
                                    holder.coord(dragAt)?.let { model.move(i, it) }
                                },
                                onDragCancel = { model.dragPreview = null },
                            )
                        },
                    contentAlignment = Alignment.Center,
                ) { HandleDot(i, model.selectedIndex == i, moving != null) }
            }
            TopChrome(model, onClose)
        }
    }
}

@Composable
private fun PlannerMap(model: PlannerModel, holder: MapHolder, density: Float) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val accent = remember {
        runCatching { Color.parseColor(Hotwire.config.pathConfiguration.settings["map_accent"] as? String ?: "#ee7f2b") }.getOrDefault(Color.rgb(238, 127, 43))
    }
    val mapView = remember { MapLibre.getInstance(context); MapView(context) }

    DisposableEffect(lifecycle) {
        mapView.onCreate(null)
        val observer = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); mapView.onDestroy() }
    }

    fun distanceToLine(p: PointF): Float {
        val pts = model.route.mapNotNull { holder.map?.projection?.toScreenLocation(LatLng(it.lat, it.lng)) }
        var best = Float.MAX_VALUE
        for (i in 0 until pts.size - 1) {
            val a = pts[i]; val b = pts[i + 1]
            val dx = b.x - a.x; val dy = b.y - a.y
            val len2 = dx * dx + dy * dy
            val t = if (len2 == 0f) 0f else (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).coerceIn(0f, 1f)
            best = minOf(best, hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
        }
        return best
    }

    fun nearHandle(p: PointF) = model.waypoints.any { w ->
        val s = holder.map?.projection?.toScreenLocation(LatLng(w.lat, w.lng)) ?: return@any false
        hypot(s.x - p.x, s.y - p.y) < HANDLE_RADIUS_DP * density
    }

    AndroidView(factory = {
        mapView.getMapAsync { map ->
            holder.map = map
            map.uiSettings.isTiltGesturesEnabled = false
            map.uiSettings.setAttributionMargins(0, 0, 0, (140 * density).toInt())
            map.uiSettings.setLogoMargins((8 * density).toInt(), 0, 0, (140 * density).toInt())
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(48.8566, 2.3522), 12.0))
            map.addOnCameraMoveListener { holder.tick++ }
            map.addOnCameraIdleListener { holder.tick++ }
            map.addOnMapLongClickListener { ll ->
                val p = map.projection.toScreenLocation(ll)
                if (!nearHandle(p)) model.add(Coord(ll.longitude, ll.latitude))
                true
            }
            map.addOnMapClickListener { ll ->
                val p = map.projection.toScreenLocation(ll)
                val c = Coord(ll.longitude, ll.latitude)
                if (model.waypoints.size >= 2 && distanceToLine(p) < LINE_TOLERANCE_DP * density) {
                    model.insert(model.insertionIndex(c), c)
                } else {
                    model.selectedIndex = null
                }
                true
            }
            val styleUrl = Hotwire.config.pathConfiguration.settings["map_style_url"] as? String ?: "https://demotiles.maplibre.org/style.json"
            map.setStyle(Style.Builder().fromUri(styleUrl)) { style ->
                val route = GeoJsonSource("planner-route").also { style.addSource(it) }
                style.addLayer(LineLayer("planner-route-casing", "planner-route").withProperties(
                    PropertyFactory.lineColor(Color.WHITE), PropertyFactory.lineWidth(9f),
                    PropertyFactory.lineCap(Property.LINE_CAP_ROUND), PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND)))
                style.addLayer(LineLayer("planner-route-line", "planner-route").withProperties(
                    PropertyFactory.lineColor(accent), PropertyFactory.lineWidth(5f),
                    PropertyFactory.lineCap(Property.LINE_CAP_ROUND), PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND)))
                val band = GeoJsonSource("planner-band").also { style.addSource(it) }
                style.addLayer(LineLayer("planner-band-line", "planner-band").withProperties(
                    PropertyFactory.lineColor(accent), PropertyFactory.lineWidth(3f), PropertyFactory.lineDasharray(arrayOf(2f, 1.5f))))
                holder.routeSource = route
                holder.bandSource = band
                holder.ready = true
            }
        }
        mapView
    }, modifier = Modifier.fillMaxSize().testTag("planner-map"))

    LaunchedEffect(holder.ready, model.route) {
        val source = holder.routeSource ?: return@LaunchedEffect
        source.setGeoJson(lineOrEmpty(model.route))
        if (model.pendingFit && model.route.size >= 2) {
            val bounds = LatLngBounds.Builder().includes(model.route.map { LatLng(it.lat, it.lng) }).build()
            holder.map?.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, 60, 200, 60, (180 * density).toInt()))
            model.pendingFit = false
        }
    }
    LaunchedEffect(holder.ready, model.dragPreview) {
        val source = holder.bandSource ?: return@LaunchedEffect
        val d = model.dragPreview
        val w = model.waypoints
        val band = if (d == null) emptyList() else listOfNotNull(w.getOrNull(d.movingIndex - 1), d.coordinate, w.getOrNull(d.movingIndex + 1))
        source.setGeoJson(lineOrEmpty(band))
    }
}

private fun lineOrEmpty(coords: List<Coord>) =
    if (coords.size >= 2) FeatureCollection.fromFeature(Feature.fromGeometry(LineString.fromLngLats(coords.map { Point.fromLngLat(it.lng, it.lat) })))
    else FeatureCollection.fromFeatures(emptyList())

@Composable
private fun HandleDot(index: Int, selected: Boolean, lifted: Boolean) {
    val accent = androidx.compose.ui.graphics.Color(0xFFEE7F2B)
    val start = index == 0
    Box(
        Modifier.scale(if (lifted) 1.35f else 1f).size(26.dp)
            .background(if (start) androidx.compose.ui.graphics.Color.White else accent, CircleShape)
            .border(if (selected) 4.dp else 3.dp, if (selected) androidx.compose.ui.graphics.Color.Blue else if (start) accent else androidx.compose.ui.graphics.Color.White, CircleShape),
        contentAlignment = Alignment.Center,
    ) { Text("${index + 1}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (start) accent else androidx.compose.ui.graphics.Color.White) }
}

@Composable
private fun TopChrome(model: PlannerModel, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth()) {
            FilledTonalIconButton(onClick = onClose, modifier = Modifier.testTag("planner-close")) { Text("✕") }
            Spacer(Modifier.weight(1f))
            FilledTonalIconButton(onClick = model::undo, enabled = model.canUndo, modifier = Modifier.testTag("planner-undo")) { Text("↶") }
            FilledTonalIconButton(onClick = model::redo, enabled = model.canRedo, modifier = Modifier.testTag("planner-redo")) { Text("↷") }
            FilledTonalIconButton(onClick = model::clear, enabled = model.waypoints.isNotEmpty(), modifier = Modifier.testTag("planner-clear")) { Text("⌫") }
        }
        model.selectedIndex?.let { i ->
            Button(onClick = { model.remove(i) }, modifier = Modifier.testTag("planner-delete-selected")) { Text("Supprimer le point ${i + 1}") }
        }
        model.error?.let { e ->
            Text(e, color = androidx.compose.ui.graphics.Color.White, fontSize = 12.sp,
                modifier = Modifier.background(androidx.compose.ui.graphics.Color.Red, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 6.dp)
                    .pointerInput(Unit) { detectTapGestures { model.error = null } })
        }
        if (model.waypoints.isEmpty()) {
            Text("Appui long sur la carte pour placer le départ", fontSize = 13.sp,
                modifier = Modifier.background(MaterialTheme.colorScheme.surface, RoundedCornerShape(50)).padding(10.dp))
        }
        // Prototype-only state line.
        Text(model.stateLine, fontFamily = FontFamily.Monospace, fontSize = 9.sp, color = androidx.compose.ui.graphics.Color.White,
            modifier = Modifier.background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.8f), RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 5.dp).testTag("planner-state"))
    }
}

@Composable
private fun Stats(model: PlannerModel) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("planner-stats")) {
        Column {
            Text(model.distanceMeters?.let { "%.1f km".format(it / 1000) } ?: "— km", fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text("Distance", fontSize = 12.sp)
        }
        Column {
            Text(model.elevationGainMeters?.let { "${it.toInt()} m" } ?: "— m", fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text("D+", fontSize = 12.sp)
        }
        if (model.isRouting) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
    }
}

@Composable
private fun SportPicker(model: PlannerModel) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { open = true }) { Text("Sport : ${PlannerModel.sports.first { it.first == model.sport }.second}") }
        DropdownMenu(open, { open = false }) {
            PlannerModel.sports.forEach { (key, label) ->
                DropdownMenuItem(text = { Text(label) }, onClick = { open = false; model.setSportAndRoute(key) })
            }
        }
    }
}

@Composable
private fun ElevationProfile(samples: List<Pair<Double, Double>>) {
    val accent = androidx.compose.ui.graphics.Color(0xFFEE7F2B)
    Canvas(Modifier.fillMaxWidth().height(120.dp)) {
        val maxX = samples.last().first.coerceAtLeast(1.0)
        val minY = samples.minOf { it.second }; val maxY = samples.maxOf { it.second }.coerceAtLeast(minY + 1)
        val path = Path()
        samples.forEachIndexed { i, (x, y) ->
            val o = Offset((x / maxX * size.width).toFloat(), (size.height - (y - minY) / (maxY - minY) * size.height).toFloat())
            if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y)
        }
        drawPath(path, accent, style = Stroke(width = 4f))
    }
}
