import Compression
import CoreLocation
import Foundation

/// Everything a finished recording session gives the review screen (#116,
/// ADR 0003) — its track, its tours, its stats and the sport it was recorded
/// under, plus the idempotency key the upload carries.
///
/// Transferred once, in one direction, when the review page connects: the web
/// side knows nothing about the ride beyond this, so whatever a handoff leaves
/// out cannot be recovered later. See `CONTEXT.md` ("Handoff").
///
/// **Stats travel precomputed and are not re-derived on the web.** A paused
/// recording drops its fixes, so from the points alone nothing can tell a pause
/// from a GPS dropout — temps écoulé is not reconstructible downstream. Only the
/// shell can compute it, so only the shell does.
struct RecordingHandoff {
    /// Wire version, so a shell newer than the page it is talking to can be told
    /// apart rather than silently misread.
    static let version = 1

    let session: RecordingSession
    let stats: RecordingStats
    let sport: Sport
    /// Minted at Arrêter and carried into `activity[recording_uuid]`. Makes an
    /// upload replayed after a kill resolve to the ride already created instead
    /// of duplicating it (S0 §5's invariant, restored — see ADR 0003).
    let recordingUuid: UUID

    init(session: RecordingSession, stats: RecordingStats, sport: Sport) {
        self.session = session
        self.stats = stats
        self.sport = sport
        // The session's own id already identifies this recording uniquely and
        // survives a kill, so a replay after relaunch mints the same key.
        self.recordingUuid = session.id
    }
}

// MARK: - Wire format

extension RecordingHandoff {
    /// The payload as the review page reads it. Point keys are terse because
    /// there are thousands of them: at ~1 Hz an hour of riding is ~3,600 points,
    /// and the field names would otherwise outweigh the data.
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

    /// The handoff as the bridge carries it: raw DEFLATE, base64'd.
    ///
    /// A six-hour ride at ~1 Hz is ~21,600 points, and the bridge's native→web
    /// leg inlines its JSON into an `evaluateJavaScript` source string — raw,
    /// that is megabytes. 1 Hz GPS text compresses roughly ten to one, which
    /// keeps even the worst realistic ride in the low hundreds of KB, so one
    /// message suffices and no chunk-reassembly is needed.
    ///
    /// Raw DEFLATE rather than gzip because `COMPRESSION_ZLIB` emits exactly
    /// that, and the web's `DecompressionStream("deflate-raw")` reads it — no
    /// gzip container or CRC32 to hand-roll on either shell.
    func encoded() throws -> String {
        let json = try JSONEncoder().encode(payload)
        return try Self.deflate(json).base64EncodedString()
    }

    private static func deflate(_ data: Data) throws -> Data {
        // Compressed output can exceed the input for incompressible data; the
        // slack keeps a pathological ride from overflowing the buffer.
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
