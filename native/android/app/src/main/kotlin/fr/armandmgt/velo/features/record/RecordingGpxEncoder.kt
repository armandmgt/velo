package fr.armandmgt.velo.features.record

import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * Serializes a finalized recording to GPX 1.1 for upload (#41, S9 — #57). Mirrors
 * the iOS `RecordingGPXEncoder`.
 *
 * Emits exactly the schema locked in the S0 contract
 * (`docs/native-recording/s0-gpx-upload-contract.md` §2), proven to round-trip by
 * the server fixture `test/fixtures/files/gpx/native_recording.gpx`. The device
 * sends **positions + time + sensors only** — distance, speed, elevation gain and
 * the PostGIS path are all derived server-side by `GpxExtractor`, so we
 * deliberately do NOT emit `<speed>` or any summary.
 *
 * All numbers are formatted with [Locale.ROOT] so decimals use `.` regardless of
 * the device locale (the app defaults to French, where `%f` would emit commas the
 * server can't parse). Timestamps are UTC ISO-8601 truncated to whole seconds.
 */
object RecordingGpxEncoder {
    /** Default track name; the server's `activity[name]` param overrides it. */
    const val DEFAULT_TRACK_NAME = "Sortie enregistrée sur le téléphone"

    fun gpx(startedAtMillis: Long, points: List<RecordingPointEntity>, sport: Sport): String {
        val lines = mutableListOf<String>()
        lines += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        lines += "<gpx creator=\"Velo Android\" version=\"1.1\""
        lines += "     xmlns=\"http://www.topografix.com/GPX/1/1\""
        lines += "     xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">"

        val metadataTime = points.firstOrNull()?.timestamp ?: startedAtMillis
        lines += " <metadata>"
        lines += "  <time>${iso8601(metadataTime)}</time>"
        lines += " </metadata>"

        lines += " <trk>"
        lines += "  <name>${xmlEscape(DEFAULT_TRACK_NAME)}</name>"
        sport.gpxType?.let { lines += "  <type>$it</type>" }
        lines += "  <trkseg>"

        points.forEach { lines += trackpoint(it) }

        lines += "  </trkseg>"
        lines += " </trk>"
        lines += "</gpx>"
        lines += ""

        return lines.joinToString("\n")
    }

    private fun trackpoint(point: RecordingPointEntity): List<String> {
        val lines = mutableListOf<String>()
        lines += "   <trkpt lat=\"${coordinate(point.latitude)}\" lon=\"${coordinate(point.longitude)}\">"
        point.elevation?.let { lines += "    <ele>${format("%.1f", it)}</ele>" }
        lines += "    <time>${iso8601(point.timestamp)}</time>"

        // Sensor extensions are wired now but null until BLE straps land (S11, #59),
        // so today nothing inside <extensions> is emitted.
        val tpx = trackPointExtension(point)
        if (tpx.isNotEmpty() || point.power != null) {
            lines += "    <extensions>"
            lines += tpx
            point.power?.let { lines += "     <power>${number(it)}</power>" }
            lines += "    </extensions>"
        }

        lines += "   </trkpt>"
        return lines
    }

    private fun trackPointExtension(point: RecordingPointEntity): List<String> {
        if (point.heartRate == null && point.cadence == null) return emptyList()
        val lines = mutableListOf<String>()
        lines += "     <gpxtpx:TrackPointExtension>"
        point.heartRate?.let { lines += "      <gpxtpx:hr>$it</gpxtpx:hr>" }
        point.cadence?.let { lines += "      <gpxtpx:cad>${number(it)}</gpxtpx:cad>" }
        lines += "     </gpxtpx:TrackPointExtension>"
        return lines
    }

    // MARK: - Formatting

    /** Decimal degrees with 7 dp (≈11 mm), matching the reference fixture. */
    private fun coordinate(value: Double): String = format("%.7f", value)

    private fun format(pattern: String, value: Double): String =
        String.format(Locale.ROOT, pattern, value)

    /** A numeric value without a trailing `.0` when whole (cadence/power). */
    private fun number(value: Double): String =
        if (value % 1.0 == 0.0 && value.isFinite()) value.toLong().toString() else value.toString()

    /** UTC ISO-8601 with a `Z` suffix, e.g. `2026-06-25T08:00:00Z` (S0 §2). */
    private fun iso8601(epochMillis: Long): String =
        Instant.ofEpochMilli(epochMillis).truncatedTo(ChronoUnit.SECONDS).toString()

    private fun xmlEscape(text: String): String =
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
}
