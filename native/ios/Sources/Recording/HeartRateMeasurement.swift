import Foundation

/// One Heart Rate Measurement notification (GATT characteristic 0x2A37), decoded.
///
/// Only the beat rate and the skin-contact flag matter to a recording. Energy
/// expended and RR intervals may follow the value; they are left unread.
struct HeartRateMeasurement: Equatable {
    enum SensorContact: Equatable {
        /// The strap can't tell whether it touches skin.
        case unsupported
        case notDetected
        case detected
    }

    let bpm: Int
    let sensorContact: SensorContact

    /// A strap taken off keeps notifying, with 0 or a frozen value, and says so
    /// by reporting no skin contact. Recording that would draw a flat line where
    /// the chart should show a gap.
    var isUsable: Bool { bpm > 0 && sensorContact != .notDetected }

    init(bpm: Int, sensorContact: SensorContact) {
        self.bpm = bpm
        self.sensorContact = sensorContact
    }

    /// `nil` when the payload is too short for the value format its flags announce.
    init?(data: Data) {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        if flags & 0x01 == 0 {
            guard bytes.count >= 2 else { return nil }
            bpm = Int(bytes[1])
        } else {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | Int(bytes[2]) << 8
        }
        // Bit 2 says contact detection is supported, bit 1 that contact is made.
        switch (flags >> 1) & 0b11 {
        case 0b11: sensorContact = .detected
        case 0b10: sensorContact = .notDetected
        default: sensorContact = .unsupported
        }
    }
}

/// The latest usable beat rate and when it arrived.
struct HeartRateReading: Equatable {
    /// How far apart (seconds) a reading and a point may be for the point to
    /// carry it. Straps notify about once a second, so this rides out a missed
    /// notification or two, but never stretches one value across a dropout.
    static let maxAge: TimeInterval = 5

    let bpm: Int
    let receivedAt: Date

    /// The beat rate for a point recorded at `date`, or `nil` when this reading
    /// is too far from it to describe it.
    func bpm(at date: Date) -> Int? {
        abs(date.timeIntervalSince(receivedAt)) <= Self.maxAge ? bpm : nil
    }
}
