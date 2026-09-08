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
 * Everything a finished recording session gives the review screen (#116,
 * ADR 0003) — its track, its tours, its stats and the sport it was recorded
 * under, plus the idempotency key the upload carries. Mirrors the iOS
 * `RecordingHandoff`.
 *
 * Transferred once, in one direction, when the review page connects: the web
 * side knows nothing about the ride beyond this, so whatever a handoff leaves
 * out cannot be recovered later. See `CONTEXT.md` ("Handoff").
 *
 * **Stats travel precomputed and are not re-derived on the web.** A paused
 * recording drops its fixes, so from the points alone nothing can tell a pause
 * from a GPS dropout — temps écoulé is not reconstructible downstream. Only the
 * shell can compute it, so only the shell does.
 */
object RecordingHandoff {
    /** Wire version, matching the iOS shell and the web's reader. */
    const val VERSION = 1

    /**
     * The finished recording waiting for the review screen to claim it.
     *
     * The review is a web page rather than an Activity that could hold the
     * session, so the handoff lives here between [RecordingActivity] finishing
     * and `bridge--recording-review` connecting. A visit to `/activities/new`
     * with none pending is the plain upload form, not a review.
     *
     * In memory only: if the process dies the ride stays in Room but nothing
     * surfaces it again — the same hole #117 covers on both platforms.
     */
    @Volatile
    var pending: Payload? = null

    /**
     * The payload as the review page reads it. Point keys are terse because
     * there are thousands of them: at ~1 Hz an hour of riding is ~3,600 points,
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
        /** The Room session id this payload came from, so it can be deleted on commit. */
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
            // The Room session id already identifies this recording uniquely and
            // survives a kill, so a replay after relaunch mints the same key.
            recordingUuid = sessionId,
            sport = sport.wire,
            startedAt = formatter.format(Date(startedAt)),
            stats = Stats(
                distance = stats.distanceMeters,
                elapsed = stats.elapsedSeconds.toDouble(),
                movingTime = stats.movingSeconds,
                averageSpeed = stats.averageSpeedMps,
            ),
            // Lap boundaries aren't persisted on Android yet — that's S12b
            // (#115). Until they are, the review renders one split covering the
            // whole ride, which is what `lapSplits` returns for no boundaries.
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
     * The handoff as the bridge carries it: raw DEFLATE, base64'd.
     *
     * A six-hour ride at ~1 Hz is ~21,600 points, and the bridge's native→web leg
     * inlines its JSON into an `evaluateJavascript` source string — raw, that is
     * megabytes. 1 Hz GPS text compresses roughly ten to one, which keeps even
     * the worst realistic ride in the low hundreds of KB, so one message suffices
     * and no chunk-reassembly is needed.
     *
     * Raw DEFLATE rather than gzip because `Deflater(nowrap = true)` emits
     * exactly that, and the web's `DecompressionStream("deflate-raw")` reads it —
     * no gzip container or CRC32 to hand-roll on either shell.
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
