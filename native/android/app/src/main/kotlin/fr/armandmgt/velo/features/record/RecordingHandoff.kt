package fr.armandmgt.velo.features.record

import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.Deflater
import kotlin.io.encoding.Base64

/**
 * What a finished recording session gives the review screen (#116, ADR 0003).
 * Mirrors the iOS `RecordingHandoff`; see `CONTEXT.md` ("Handoff").
 *
 * Stats travel precomputed rather than derived on the web: a paused recording
 * drops its fixes, so from the points alone nothing can tell a pause from a GPS
 * dropout, and temps écoulé is not reconstructible downstream.
 */
object RecordingHandoff {
    /** Wire version, matching the iOS shell and the web's reader. */
    const val VERSION = 1

    /**
     * Lives here between [RecordingActivity] finishing and the bridge component
     * connecting, since the review is a web page rather than an Activity that
     * could hold the session.
     *
     * In memory only: if the process dies the ride stays in Room but nothing
     * surfaces it again (#117).
     */
    @Volatile
    var pending: Payload? = null

    /**
     * Point keys are terse because at ~1 Hz an hour of riding is ~3,600 of them,
     * and the field names would otherwise outweigh the data.
     */
    @Serializable
    data class Payload(
        val version: Int = VERSION,
        val recordingUuid: String,
        val sport: String,
        val startedAt: String,
        val stats: Stats,
        val laps: List<Lap>,
        val points: List<Point>,
    ) {
        /** The Room session id, so the row can be deleted on commit. */
        @kotlinx.serialization.Transient
        var sessionId: String = ""
    }

    @Serializable
    data class Stats(
        val distance: Double,
        val elapsed: Double,
        val movingTime: Double,
        val averageSpeed: Double,
    )

    @Serializable
    data class Lap(
        val ordinal: Int,
        val cumulativeDistance: Double,
        val cumulativeElapsed: Double,
    )

    @Serializable
    data class Point(
        val t: String,
        val lat: Double,
        val lon: Double,
        val ele: Double? = null,
        val hr: Int? = null,
        val cad: Double? = null,
        val pw: Double? = null,
    )

    private val json = Json { encodeDefaults = true; explicitNulls = false }

    private val iso8601: SimpleDateFormat
        get() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

    fun build(
        sessionId: String,
        startedAt: Long,
        sport: Sport,
        stats: RecordingUiState,
        points: List<RecordingPointEntity>,
    ): Payload {
        val formatter = iso8601
        return Payload(
            // The session id survives a kill, so a replay mints the same key.
            recordingUuid = sessionId,
            sport = sport.wire,
            startedAt = formatter.format(Date(startedAt)),
            stats = Stats(
                distance = stats.distanceMeters,
                elapsed = stats.elapsedSeconds.toDouble(),
                movingTime = stats.movingSeconds,
                averageSpeed = stats.averageSpeedMps,
            ),
            // Lap boundaries aren't persisted on Android yet (#115); until they
            // are, the review renders one split covering the whole ride.
            laps = emptyList(),
            points = points.map { point ->
                Point(
                    t = formatter.format(Date(point.timestamp)),
                    lat = point.latitude,
                    lon = point.longitude,
                    ele = point.elevation,
                    hr = point.heartRate,
                    cad = point.cadence,
                    pw = point.power,
                )
            },
        ).also { it.sessionId = sessionId }
    }

    /**
     * Raw DEFLATE, base64'd. The bridge's native→web leg inlines its JSON into an
     * `evaluateJavascript` source string, and a six-hour ride is ~21,600 points —
     * 1.5 MB raw, ~250 KB compressed, so one message suffices.
     *
     * Raw DEFLATE rather than gzip because `Deflater(nowrap = true)` emits
     * exactly that and the web reads it with `DecompressionStream("deflate-raw")`.
     */
    @OptIn(kotlin.io.encoding.ExperimentalEncodingApi::class)
    fun encode(payload: Payload): String {
        val bytes = json.encodeToString(payload).toByteArray(Charsets.UTF_8)
        return Base64.encode(deflate(bytes))
    }

    private fun deflate(input: ByteArray): ByteArray {
        val deflater = Deflater(Deflater.BEST_SPEED, true)
        try {
            deflater.setInput(input)
            deflater.finish()

            val output = java.io.ByteArrayOutputStream(input.size / 4 + 1024)
            val buffer = ByteArray(16 * 1024)
            while (!deflater.finished()) {
                output.write(buffer, 0, deflater.deflate(buffer))
            }
            return output.toByteArray()
        } finally {
            deflater.end()
        }
    }
}
