package fr.armandmgt.velo.features.record

import fr.armandmgt.velo.features.record.data.RecordingPointEntity
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.Locale

/**
 * Guards the GPX contract (#57), in particular that numbers are formatted
 * locale-independently — the app defaults to French, where `%f` would emit comma
 * decimals the server's `GpxExtractor` can't parse.
 */
class RecordingGpxEncoderTest {
    private lateinit var previousLocale: Locale

    @Before
    fun forceFrenchLocale() {
        previousLocale = Locale.getDefault()
        // The riskiest case: a locale whose default decimal separator is a comma.
        Locale.setDefault(Locale.FRANCE)
    }

    @After
    fun restoreLocale() {
        Locale.setDefault(previousLocale)
    }

    // 2026-06-14T08:00:00Z and one second later, with millis that must be dropped.
    private val t0 = 1781424000000L
    private val t1 = t0 + 1000L

    @Test
    fun `coordinates and elevation use dot decimals regardless of locale`() {
        val gpx = RecordingGpxEncoder.gpx(
            startedAtMillis = t0,
            points = listOf(
                RecordingPointEntity(sessionId = "s", timestamp = t0, latitude = 48.8566, longitude = 2.3522, elevation = 35.0),
            ),
            sport = Sport.BIKE,
        )

        assertTrue(gpx, gpx.contains("lat=\"48.8566000\" lon=\"2.3522000\""))
        assertTrue(gpx, gpx.contains("<ele>35.0</ele>"))
        assertFalse("no comma decimals", gpx.contains(","))
    }

    @Test
    fun `header carries the Android creator and the sport type`() {
        val gpx = RecordingGpxEncoder.gpx(t0, emptyList(), Sport.GRAVEL_RIDE)

        assertTrue(gpx, gpx.contains("creator=\"Velo Android\""))
        assertTrue(gpx, gpx.contains("<type>gravelbiking</type>"))
    }

    @Test
    fun `workout omits the trk type since it has no GPX mapping`() {
        val gpx = RecordingGpxEncoder.gpx(t0, emptyList(), Sport.WORKOUT)

        assertFalse(gpx, gpx.contains("<type>"))
    }

    @Test
    fun `timestamps are UTC and truncated to whole seconds`() {
        val gpx = RecordingGpxEncoder.gpx(
            t0,
            listOf(
                RecordingPointEntity(sessionId = "s", timestamp = t0 + 750L, latitude = 1.0, longitude = 2.0),
            ),
            Sport.RUN,
        )

        assertTrue(gpx, gpx.contains("<time>2026-06-14T08:00:00Z</time>"))
    }

    @Test
    fun `sensor extensions are emitted only when present`() {
        val withSensors = RecordingGpxEncoder.gpx(
            t0,
            listOf(
                RecordingPointEntity(
                    sessionId = "s", timestamp = t0, latitude = 1.0, longitude = 2.0,
                    heartRate = 112, cadence = 84.0, power = 180.0,
                ),
            ),
            Sport.BIKE,
        )
        assertTrue(withSensors, withSensors.contains("<gpxtpx:hr>112</gpxtpx:hr>"))
        assertTrue(withSensors, withSensors.contains("<gpxtpx:cad>84</gpxtpx:cad>"))
        assertTrue(withSensors, withSensors.contains("<power>180</power>"))

        val withoutSensors = RecordingGpxEncoder.gpx(
            t0,
            listOf(RecordingPointEntity(sessionId = "s", timestamp = t1, latitude = 1.0, longitude = 2.0)),
            Sport.BIKE,
        )
        assertFalse(withoutSensors, withoutSensors.contains("<extensions>"))
    }
}
