package fr.armandmgt.velo.features.record

import android.location.Location
import fr.armandmgt.velo.features.record.data.RecordingDao
import fr.armandmgt.velo.features.record.data.RecordingLapEntity
import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import fr.armandmgt.velo.features.record.data.RecordingSessionEntity
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
 * What a finished recording gives the review screen. Mirrors the iOS
 * `RecordingHandoff`.
 *
 * Stats travel precomputed: a paused recording drops its fixes, so from the
 * points alone nothing can tell a pause from a GPS dropout.
 *
 * Always built from the stored session ([load]) — at Arrêter just after the
 * totals are written, and later for an unsent recording — so a resent review is
 * the same handoff the first one was.
 */
object RecordingHandoff {
    const val VERSION = 1

    /**
     * The recording the next review page opens on, set by Arrêter or by Envoyer on
     * an unsent recording. The review is a web page rather than an Activity that
     * could be handed it directly; the bridge component picks it up on connect.
     */
    @Volatile
    var pending: Payload? = null

    /**
     * Terse keys: at ~1 Hz an hour of riding is ~3,600 points, and the field
     * names would otherwise outweigh the data.
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

    /**
     * The handoff for a stored session, or null when there is nothing to review
     * (no such session, or no points). [fallbackSport] covers sessions recorded
     * before the sport was stored.
     */
    suspend fun load(dao: RecordingDao, sessionId: String, fallbackSport: Sport): Payload? {
        val session = dao.session(sessionId) ?: return null
        val points = dao.pointsFor(sessionId)
        if (points.isEmpty()) return null
        return build(session, points, dao.lapsFor(sessionId), fallbackSport)
    }

    fun build(
        session: RecordingSessionEntity,
        points: List<RecordingPointEntity>,
        laps: List<RecordingLapEntity>,
        fallbackSport: Sport,
    ): Payload {
        val formatter = iso8601
        return Payload(
            // Survives a kill, so a replay mints the same key.
            recordingUuid = session.id,
            sport = sportOf(session, fallbackSport).wire,
            startedAt = formatter.format(Date(points.first().timestamp)),
            stats = finalStats(session, points),
            laps = laps.map { lap ->
                Lap(
                    ordinal = lap.ordinal,
                    cumulativeDistance = lap.cumulativeDistance,
                    cumulativeElapsed = lap.cumulativeElapsed,
                )
            },
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
        ).also { it.sessionId = session.id }
    }

    fun sportOf(session: RecordingSessionEntity, fallback: Sport): Sport =
        Sport.entries.firstOrNull { it.wire == session.sport } ?: fallback

    /**
     * The totals a recording ended with: the ones stored at Arrêter, or, for a
     * session stopped without them, totals derived from its [points]. A running
     * temps écoulé snapshot beats the point span when one was kept.
     */
    fun finalStats(session: RecordingSessionEntity, points: List<RecordingPointEntity>): Stats {
        if (session.stoppedAt != null) {
            return Stats(session.distance, session.elapsed, session.movingTime, session.averageSpeed)
        }
        val derived = derivedStats(points)
        return if (session.elapsed > 0) derived.copy(elapsed = session.elapsed) else derived
    }

    /**
     * Distance and durée de déplacement replay the accumulator over the stored
     * points; temps écoulé falls back to the first-to-last span, which counts any
     * pause as riding because pauses leave no trace in the points.
     */
    fun derivedStats(points: List<RecordingPointEntity>): Stats {
        val accumulator = RecordingStatsAccumulator()
        for (point in points) {
            accumulator.add(
                Location("recording").apply {
                    latitude = point.latitude
                    longitude = point.longitude
                    time = point.timestamp
                },
            )
        }
        val span = if (points.isEmpty()) 0.0 else (points.last().timestamp - points.first().timestamp) / 1000.0
        return Stats(accumulator.distance, span, accumulator.movingSeconds, accumulator.averageSpeed())
    }

    /**
     * The bridge inlines this into an `evaluateJavascript` source string, and a
     * six-hour ride is 1.5 MB raw against ~250 KB compressed, so one message
     * suffices. DEFLATE rather than gzip because that is what
     * `Deflater(nowrap = true)` emits and what the web reads back.
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
