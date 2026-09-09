import Compression
import CoreLocation
import Foundation

/// What a finished recording gives the review screen (#116; `CONTEXT.md`).
///
/// Stats travel precomputed: a paused recording drops its fixes, so from the
/// points alone nothing can tell a pause from a GPS dropout, and temps écoulé is
/// not reconstructible downstream.
struct RecordingHandoff {
    static let version = 1

    let session: RecordingSession
    let stats: RecordingStats
    let sport: Sport
    /// Makes an upload replayed after a kill resolve to the ride already created.
    let recordingUuid: UUID

    init(session: RecordingSession, stats: RecordingStats, sport: Sport) {
        self.session = session
        self.stats = stats
        self.sport = sport
        // The session id survives a kill, so a replay mints the same key.
        self.recordingUuid = session.id
    }
}

// MARK: - Wire format

extension RecordingHandoff {
    /// Point keys are terse because at ~1 Hz an hour of riding is ~3,600 of
    /// them, and the field names would otherwise outweigh the data.
    private struct Payload: Encodable {
        let version: Int
        let recordingUuid: String
        let sport: String
        let startedAt: String
        let stats: Stats
        let laps: [Lap]
        let points: [Point]

        struct Stats: Encodable {
            let distance: Double
            let elapsed: Double
            let movingTime: Double
            let averageSpeed: Double
        }

        struct Lap: Encodable {
            let ordinal: Int
            let cumulativeDistance: Double
            let cumulativeElapsed: Double
        }

        struct Point: Encodable {
            let t: String
            let lat: Double
            let lon: Double
            let ele: Double?
            let hr: Int?
            let cad: Double?
            let pw: Double?
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private var payload: Payload {
        Payload(
            version: Self.version,
            recordingUuid: recordingUuid.uuidString.lowercased(),
            sport: sport.rawValue,
            startedAt: Self.iso8601.string(from: session.startedAt),
            stats: .init(
                distance: stats.distance,
                elapsed: stats.elapsed,
                movingTime: stats.movingTime,
                averageSpeed: stats.averageSpeed
            ),
            laps: session.lapBoundaries.map {
                .init(
                    ordinal: $0.ordinal,
                    cumulativeDistance: $0.cumulativeDistance,
                    cumulativeElapsed: $0.cumulativeElapsed
                )
            },
            points: session.orderedPoints.map {
                .init(
                    t: Self.iso8601.string(from: $0.timestamp),
                    lat: $0.latitude,
                    lon: $0.longitude,
                    ele: $0.hasElevation ? $0.elevation : nil,
                    hr: $0.hasHeartRate ? Int($0.heartRate) : nil,
                    cad: $0.hasCadence ? $0.cadence : nil,
                    pw: $0.hasPower ? $0.power : nil
                )
            }
        )
    }

    /// Raw DEFLATE, base64'd. The bridge inlines its JSON into an
    /// `evaluateJavaScript` source string, and a six-hour ride is 1.5 MB raw
    /// against ~250 KB compressed — so one message suffices. DEFLATE rather than
    /// gzip because `COMPRESSION_ZLIB` emits exactly what the web's
    /// `DecompressionStream("deflate-raw")` reads.
    func encoded() throws -> String {
        let json = try JSONEncoder().encode(payload)
        return try Self.deflate(json).base64EncodedString()
    }

    private static func deflate(_ data: Data) throws -> Data {
        // Compressed output can exceed the input for incompressible data.
        let capacity = data.count + (data.count / 2) + 1024
        var destination = Data(count: capacity)

        let written = destination.withUnsafeMutableBytes { destinationBuffer in
            data.withUnsafeBytes { sourceBuffer in
                compression_encode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { throw HandoffError.compressionFailed }
        return destination.prefix(written)
    }

    enum HandoffError: Error {
        case compressionFailed
    }
}
