import Foundation
import Testing
@testable import Velo

/// Decoding the strap's Heart Rate Measurement notifications, and the rule that
/// decides whether a point may carry the latest reading. Mirrors the Android
/// `HeartRateMeasurementTest`.
@Suite("HeartRateMeasurement")
struct HeartRateMeasurementTests {
    private func measurement(_ bytes: [UInt8]) -> HeartRateMeasurement? {
        HeartRateMeasurement(data: Data(bytes))
    }

    @Test("an 8-bit value is read from the byte after the flags")
    func eightBit() {
        #expect(measurement([0x00, 72]) == HeartRateMeasurement(bpm: 72, sensorContact: .unsupported))
    }

    @Test("an 8-bit value uses the whole unsigned range")
    func eightBitUnsigned() {
        #expect(measurement([0x00, 0xC8])?.bpm == 200)
    }

    @Test("a 16-bit value is little-endian")
    func sixteenBit() {
        #expect(measurement([0x01, 0x2C, 0x01])?.bpm == 300)
        #expect(measurement([0x01, 0x8C, 0x00])?.bpm == 140)
    }

    @Test("contact supported and detected")
    func contactDetected() {
        let decoded = measurement([0x06, 150])
        #expect(decoded?.sensorContact == .detected)
        #expect(decoded?.isUsable == true)
    }

    @Test("contact supported but lost makes the reading unusable")
    func contactLost() {
        let decoded = measurement([0x04, 150])
        #expect(decoded?.bpm == 150)
        #expect(decoded?.sensorContact == .notDetected)
        #expect(decoded?.isUsable == false)
    }

    @Test("a strap without contact detection is trusted")
    func contactUnsupported() {
        #expect(measurement([0x02, 150])?.sensorContact == .unsupported)
        #expect(measurement([0x02, 150])?.isUsable == true)
    }

    @Test("contact flags combine with the 16-bit format")
    func contactWithSixteenBit() {
        #expect(measurement([0x07, 0x8C, 0x00]) == HeartRateMeasurement(bpm: 140, sensorContact: .detected))
    }

    @Test("RR intervals after an 8-bit value are ignored")
    func rrIntervalsEightBit() {
        // Flags: RR present (bit 4) + contact detected; two intervals of ~0.8 s.
        #expect(measurement([0x16, 75, 0x33, 0x03, 0x30, 0x03]) == HeartRateMeasurement(bpm: 75, sensorContact: .detected))
    }

    @Test("energy expended and RR intervals after a 16-bit value are ignored")
    func energyAndRRSixteenBit() {
        // Flags: 16-bit + contact detected + energy (bit 3) + RR (bit 4).
        #expect(measurement([0x1F, 0x96, 0x00, 0x10, 0x00, 0x00, 0x02])?.bpm == 150)
    }

    @Test("a zero beat rate is unusable")
    func zero() {
        #expect(measurement([0x00, 0])?.isUsable == false)
    }

    @Test("a payload too short for its format is rejected")
    func truncated() {
        #expect(measurement([]) == nil)
        #expect(measurement([0x00]) == nil)
        #expect(measurement([0x01, 0x8C]) == nil)
    }
}

@Suite("HeartRateReading")
struct HeartRateReadingTests {
    private let received = Date(timeIntervalSince1970: 1_000)

    @Test("a point recorded with the reading carries it")
    func fresh() {
        #expect(HeartRateReading(bpm: 140, receivedAt: received).bpm(at: received) == 140)
    }

    @Test("a reading up to the maximum age still counts")
    func atMaxAge() {
        let reading = HeartRateReading(bpm: 140, receivedAt: received)
        #expect(reading.bpm(at: received.addingTimeInterval(HeartRateReading.maxAge)) == 140)
    }

    @Test("an older reading leaves the point without heart rate")
    func stale() {
        let reading = HeartRateReading(bpm: 140, receivedAt: received)
        #expect(reading.bpm(at: received.addingTimeInterval(HeartRateReading.maxAge + 1)) == nil)
    }

    @Test("a reading that arrived just after the fix still describes it")
    func slightlyAfterTheFix() {
        let reading = HeartRateReading(bpm: 140, receivedAt: received)
        #expect(reading.bpm(at: received.addingTimeInterval(-1)) == 140)
        #expect(reading.bpm(at: received.addingTimeInterval(-HeartRateReading.maxAge - 1)) == nil)
    }
}
