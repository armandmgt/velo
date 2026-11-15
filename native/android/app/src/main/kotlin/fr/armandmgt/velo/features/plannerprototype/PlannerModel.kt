// PROTOTYPE — throwaway native route planner spike (wayfinder #21, branch
// prototype/native-route-planner). Not production code: no tests, minimal errors.
package fr.armandmgt.velo.features.plannerprototype

import android.webkit.CookieManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import fr.armandmgt.velo.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

data class Coord(val lng: Double, val lat: Double)

/** A waypoint being dragged, drawn as a dashed rubber band until release. */
data class DragPreview(val movingIndex: Int, val coordinate: Coord)

class PlannerModel(private val scope: CoroutineScope) {
    var waypoints by mutableStateOf(listOf<Coord>()); private set
    var route by mutableStateOf(listOf<Coord>()); private set
    var distanceMeters by mutableStateOf<Double?>(null); private set
    var elevationGainMeters by mutableStateOf<Double?>(null); private set
    var elevationSamples by mutableStateOf(listOf<Pair<Double, Double>>()); private set
    var name by mutableStateOf("")
    var sport by mutableStateOf("bike")
    var selectedIndex by mutableStateOf<Int?>(null)
    var dragPreview by mutableStateOf<DragPreview?>(null)
    var isRouting by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var lastAction by mutableStateOf("—"); private set
    var previewCount by mutableIntStateOf(0); private set
    var pendingFit by mutableStateOf(false)

    private val history = ArrayDeque<List<Coord>>()
    private val future = ArrayDeque<List<Coord>>()
    private var previewJob: Job? = null
    var canUndo by mutableStateOf(false); private set
    var canRedo by mutableStateOf(false); private set

    fun add(c: Coord) = set(waypoints + c, "ajout #${waypoints.size + 1}")

    fun move(i: Int, c: Coord) {
        if (i !in waypoints.indices) return
        set(waypoints.toMutableList().also { it[i] = c }, "déplacement #${i + 1}")
    }

    fun insert(i: Int, c: Coord) {
        set(waypoints.toMutableList().also { it.add(i.coerceIn(0, it.size), c) }, "insertion #${i + 1}")
        selectedIndex = null
    }

    fun remove(i: Int) {
        if (i !in waypoints.indices) return
        set(waypoints.toMutableList().also { it.removeAt(i) }, "suppression #${i + 1}")
        selectedIndex = null
    }

    fun clear() = set(emptyList(), "effacer")

    fun undo() {
        val prev = history.removeLastOrNull() ?: return
        future.addLast(waypoints)
        apply(prev, "annuler")
    }

    fun redo() {
        val next = future.removeLastOrNull() ?: return
        history.addLast(waypoints)
        apply(next, "rétablir")
    }

    fun setSportAndRoute(s: String) {
        sport = s
        schedulePreview()
    }

    private fun set(next: List<Coord>, action: String) {
        if (next == waypoints) return
        history.addLast(waypoints)
        future.clear()
        apply(next, action)
    }

    private fun apply(next: List<Coord>, action: String) {
        waypoints = next
        lastAction = action
        canUndo = history.isNotEmpty()
        canRedo = future.isNotEmpty()
        if (selectedIndex?.let { it !in next.indices } == true) selectedIndex = null
        schedulePreview()
    }

    /** Ported from route_planner_controller.js: bracket the touched route index. */
    fun insertionIndex(c: Coord): Int {
        if (route.size < 2) return waypoints.size
        val hit = nearestRouteIndex(c)
        val indices = waypoints.map(::nearestRouteIndex)
        for (i in 0 until indices.size - 1) if (hit >= indices[i] && hit <= indices[i + 1]) return i + 1
        return waypoints.size
    }

    private fun nearestRouteIndex(c: Coord): Int =
        route.indices.minByOrNull { val r = route[it]; (r.lng - c.lng) * (r.lng - c.lng) + (r.lat - c.lat) * (r.lat - c.lat) } ?: 0

    private fun schedulePreview() {
        previewJob?.cancel()
        if (waypoints.size < 2) {
            route = emptyList(); distanceMeters = null; elevationGainMeters = null; elevationSamples = emptyList()
            return
        }
        val points = waypoints
        val s = sport
        previewJob = scope.launch {
            delay(250)
            isRouting = true
            try {
                val body = buildJsonObject {
                    put("sport", s)
                    putJsonArray("waypoints") { points.forEach { p -> add(JsonArray(listOf(JsonPrimitive(p.lng), JsonPrimitive(p.lat)))) } }
                }
                val json = PlannerApi.post("/planned_routes/preview", body.toString().toByteArray(), "application/json")
                route = json["coordinates"]?.jsonArray?.map { val a = it.jsonArray; Coord(a[0].jsonPrimitive.double, a[1].jsonPrimitive.double) }.orEmpty()
                distanceMeters = json["distance_meters"]?.jsonPrimitive?.doubleOrNull
                elevationGainMeters = json["elevation_gain_meters"]?.jsonPrimitive?.doubleOrNull
                elevationSamples = (json["elevation_samples"] as? JsonArray)?.map { val a = it.jsonArray; a[0].jsonPrimitive.double to a[1].jsonPrimitive.double }.orEmpty()
                error = null
                previewCount += 1
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message
            } finally {
                isRouting = false
            }
        }
    }

    fun importGpx(bytes: ByteArray, filename: String) = scope.launch {
        try {
            val boundary = "velo-${UUID.randomUUID()}"
            val body = "--$boundary\r\nContent-Disposition: form-data; name=\"gpx_source\"; filename=\"$filename\"\r\nContent-Type: application/gpx+xml\r\n\r\n".toByteArray() +
                bytes + "\r\n--$boundary--\r\n".toByteArray()
            val json = PlannerApi.post("/planned_routes/import_gpx", body, "multipart/form-data; boundary=$boundary")
            val points = json["waypoints"]?.jsonArray?.map { val a = it.jsonArray; Coord(a[0].jsonPrimitive.double, a[1].jsonPrimitive.double) }.orEmpty()
            if (name.isEmpty()) json["name"]?.jsonPrimitive?.contentOrNull?.let { name = it }
            pendingFit = true
            set(points, "import GPX (${points.size} pts)")
        } catch (e: Exception) {
            error = e.message
        }
    }

    suspend fun save(): String? = try {
        val waypointsJson = JsonArray(waypoints.map { JsonArray(listOf(JsonPrimitive(it.lng), JsonPrimitive(it.lat))) }).toString()
        val body = buildJsonObject {
            put("planned_route", buildJsonObject {
                put("name", name.ifEmpty { "Itinéraire" }); put("sport", sport); put("visibility", "private"); put("waypoints_json", waypointsJson)
            })
        }
        PlannerApi.post("/planned_routes", body.toString().toByteArray(), "application/json")["url"]?.jsonPrimitive?.contentOrNull
    } catch (e: Exception) {
        error = e.message
        null
    }

    val stateLine: String
        get() = "${waypoints.size} pts · ${route.size} seg · sel ${selectedIndex?.let { "#${it + 1}" } ?: "—"} · $lastAction · ${if (isRouting) "routage…" else "ok #$previewCount"}"

    companion object {
        val sports = listOf(
            "bike" to "Vélo", "gravel_ride" to "Gravel", "mountain_bike_ride" to "VTT", "e_bike_ride" to "VAE",
            "run" to "Course", "trail_run" to "Trail", "walk" to "Marche", "hike" to "Randonnée",
        )
    }
}

/** PROTOTYPE: rides the webview cookie; the real design is bearer auth (#10). */
object PlannerApi {
    suspend fun post(path: String, body: ByteArray, contentType: String): JsonObject = withContext(Dispatchers.IO) {
        val url = "${BuildConfig.BASE_URL}$path"
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.setRequestProperty("Content-Type", contentType)
        conn.setRequestProperty("Accept", "application/json")
        CookieManager.getInstance().getCookie(url)?.let { conn.setRequestProperty("Cookie", it) }
        conn.outputStream.use { it.write(body) }
        val status = conn.responseCode
        val text = (if (status in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText().orEmpty()
        val json = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrDefault(JsonObject(emptyMap()))
        if (status !in 200..299) throw IllegalStateException("${json["error"]?.jsonPrimitive?.contentOrNull ?: "http_error"} ($status)")
        json
    }
}
