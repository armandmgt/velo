package fr.armandmgt.velo.features.record

import fr.armandmgt.velo.features.record.HeartRateMeasurement.SensorContact
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Decoding the strap's Heart Rate Measurement notifications, and the rule that
 * decides whether a point may carry the latest reading. Mirrors the iOS
 * `HeartRateMeasurementTests`.
 */
class HeartRateMeasurementTest {
    private fun measurement(vararg bytes: Int) =
        HeartRateMeasurement.parse(ByteArray(bytes.size) { bytes[it].toByte() })

    @Test
    fun `an 8-bit value is read from the byte after the flags`() {
        assertEquals(HeartRateMeasurement(72, SensorContact.UNSUPPORTED), measurement(0x00, 72))
    }

    @Test
    fun `an 8-bit value uses the whole unsigned range`() {
        assertEquals(200, measurement(0x00, 0xC8)?.bpm)
    }

    @Test
    fun `a 16-bit value is little-endian`() {
        assertEquals(300, measurement(0x01, 0x2C, 0x01)?.bpm)
        assertEquals(140, measurement(0x01, 0x8C, 0x00)?.bpm)
    }

    @Test
    fun `contact supported and detected`() {
        val decoded = measurement(0x06, 150)
        assertEquals(SensorContact.DETECTED, decoded?.sensorContact)
        assertTrue(decoded!!.isUsable)
    }

    @Test
    fun `contact supported but lost makes the reading unusable`() {
        val decoded = measurement(0x04, 150)
        assertEquals(150, decoded?.bpm)
        assertEquals(SensorContact.NOT_DETECTED, decoded?.sensorContact)
        assertFalse(decoded!!.isUsable)
    }

    @Test
    fun `a strap without contact detection is trusted`() {
        val decoded = measurement(0x02, 150)
        assertEquals(SensorContact.UNSUPPORTED, decoded?.sensorContact)
        assertTrue(decoded!!.isUsable)
    }

    @Test
    fun `contact flags combine with the 16-bit format`() {
        assertEquals(HeartRateMeasurement(140, SensorContact.DETECTED), measurement(0x07, 0x8C, 0x00))
    }

    @Test
    fun `RR intervals after an 8-bit value are ignored`() {
        // Flags: RR present (bit 4) + contact detected; two intervals of ~0.8 s.
        assertEquals(
            HeartRateMeasurement(75, SensorContact.DETECTED),
            measurement(0x16, 75, 0x33, 0x03, 0x30, 0x03),
        )
    }

    @Test
    fun `energy expended and RR intervals after a 16-bit value are ignored`() {
        // Flags: 16-bit + contact detected + energy (bit 3) + RR (bit 4).
        assertEquals(150, measurement(0x1F, 0x96, 0x00, 0x10, 0x00, 0x00, 0x02)?.bpm)
    }

    @Test
    fun `a zero beat rate is unusable`() {
        assertFalse(measurement(0x00, 0)!!.isUsable)
    }

    @Test
    fun `a payload too short for its format is rejected`() {
        assertNull(measurement())
        assertNull(measurement(0x00))
        assertNull(measurement(0x01, 0x8C))
    }
}

class HeartRateReadingTest {
    private val received = 1_000_000L

    @Test
    fun `a point recorded with the reading carries it`() {
        assertEquals(140, HeartRateReading(140, received).bpmAt(received))
    }

    @Test
    fun `a reading up to the maximum age still counts`() {
        assertEquals(140, HeartRateReading(140, received).bpmAt(received + HeartRateReading.MAX_AGE_MS))
    }

    @Test
    fun `an older reading leaves the point without heart rate`() {
        assertNull(HeartRateReading(140, received).bpmAt(received + HeartRateReading.MAX_AGE_MS + 1_000))
    }

    @Test
    fun `a reading that arrived just after the fix still describes it`() {
        val reading = HeartRateReading(140, received)
        assertEquals(140, reading.bpmAt(received - 1_000))
        assertNull(reading.bpmAt(received - HeartRateReading.MAX_AGE_MS - 1_000))
    }
}
