package fr.armandmgt.velo.features.record

import kotlin.math.abs

/**
 * One Heart Rate Measurement notification (GATT characteristic 0x2A37), decoded.
 *
 * Only the beat rate and the skin-contact flag matter to a recording. Energy
 * expended and RR intervals may follow the value; they are left unread.
 */
data class HeartRateMeasurement(val bpm: Int, val sensorContact: SensorContact) {
    enum class SensorContact {
        /** The strap can't tell whether it touches skin. */
        UNSUPPORTED,
        NOT_DETECTED,
        DETECTED,
    }

    /**
     * A strap taken off keeps notifying, with 0 or a frozen value, and says so by
     * reporting no skin contact. Recording that would draw a flat line where the
     * chart should show a gap.
     */
    val isUsable: Boolean get() = bpm > 0 && sensorContact != SensorContact.NOT_DETECTED

    companion object {
        /** Null when the payload is too short for the value format its flags announce. */
        fun parse(bytes: ByteArray): HeartRateMeasurement? {
            val flags = bytes.firstOrNull()?.toInt()?.and(0xFF) ?: return null
            val bpm = if (flags and 0x01 == 0) {
                if (bytes.size < 2) return null
                bytes[1].toInt() and 0xFF
            } else {
                if (bytes.size < 3) return null
                (bytes[1].toInt() and 0xFF) or ((bytes[2].toInt() and 0xFF) shl 8)
            }
            // Bit 2 says contact detection is supported, bit 1 that contact is made.
            val contact = when ((flags shr 1) and 0b11) {
                0b11 -> SensorContact.DETECTED
                0b10 -> SensorContact.NOT_DETECTED
                else -> SensorContact.UNSUPPORTED
            }
            return HeartRateMeasurement(bpm, contact)
        }
    }
}

/** The latest usable beat rate and when it arrived (wall clock, like a fix's time). */
data class HeartRateReading(val bpm: Int, val receivedAtMs: Long) {
    /**
     * The beat rate for a point recorded at [timeMs], or null when this reading is
     * too far from it to describe it.
     */
    fun bpmAt(timeMs: Long): Int? = if (abs(timeMs - receivedAtMs) <= MAX_AGE_MS) bpm else null

    companion object {
        /**
         * How far apart a reading and a point may be for the point to carry it.
         * Straps notify about once a second, so this rides out a missed
         * notification or two, but never stretches one value across a dropout.
         */
        const val MAX_AGE_MS = 5_000L
    }
}
