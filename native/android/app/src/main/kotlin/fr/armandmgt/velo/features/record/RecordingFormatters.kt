package fr.armandmgt.velo.features.record

/**
 * Shared formatting for recording numbers, so the dock and the split sheet render
 * identical figures. Mirrors the iOS `RecordingFormatters`.
 */
object RecordingFormatters {
    /** `x.xx` km from a distance in meters. */
    fun distanceKilometers(meters: Double): String = "%.2f".format(meters / 1000)

    /** `H:MM:SS` once past an hour, else `MM:SS`. */
    fun elapsed(seconds: Double): String {
        val total = seconds.toLong().coerceAtLeast(0)
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    /**
     * `m:ss/km`. Instantaneous pace is inherently jumpy, so near-zero speed reads
     * as `—` rather than an absurd figure.
     */
    fun pace(metersPerSecond: Double): String {
        if (metersPerSecond <= 0.3) return "—"
        val secondsPerKm = 1000 / metersPerSecond
        val minutes = (secondsPerKm / 60).toInt()
        val seconds = (secondsPerKm % 60).toInt()
        return "%d:%02d/km".format(minutes, seconds)
    }

    fun speed(metersPerSecond: Double): String = "%.1f km/h".format(maxOf(metersPerSecond, 0.0) * 3.6)

    /** Speed (km/h) or pace (min/km) per the sport. */
    fun speedOrPace(metersPerSecond: Double, usesPace: Boolean): String =
        if (usesPace) pace(metersPerSecond) else speed(metersPerSecond)
}
