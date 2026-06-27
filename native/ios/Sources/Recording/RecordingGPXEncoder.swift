import Foundation

/// Serializes a finalized `RecordingSession` to GPX 1.1 for upload (#41, S4 — #52).
///
/// Emits exactly the schema locked in the S0 contract
/// (`docs/native-recording/s0-gpx-upload-contract.md` §2), proven to round-trip
/// by the server fixture `test/fixtures/files/gpx/native_recording.gpx`. The
/// device sends **positions + time + sensors only** — distance, speed, elevation
/// gain and the PostGIS path are all derived server-side by `GpxExtractor`, so we
/// deliberately do NOT emit `<speed>` or any summary.
enum RecordingGPXEncoder {
    /// Default track name when the user didn't name the activity; a fallback the
    /// server's `activity[name]` param (and the awaiting-name prompt) override.
    static let defaultTrackName = "Sortie enregistrée sur le téléphone"

    static func gpx(for session: RecordingSession, sport: Sport) -> String {
        let points = session.orderedPoints

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<gpx creator=\"Velo iOS\" version=\"1.1\"")
        lines.append("     xmlns=\"http://www.topografix.com/GPX/1/1\"")
        lines.append("     xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">")

        let metadataTime = points.first?.timestamp ?? session.startedAt
        lines.append(" <metadata>")
        lines.append("  <time>\(iso8601(metadataTime))</time>")
        lines.append(" </metadata>")

        lines.append(" <trk>")
        lines.append("  <name>\(xmlEscape(defaultTrackName))</name>")
        if let type = sport.gpxType {
            lines.append("  <type>\(type)</type>")
        }
        lines.append("  <trkseg>")

        for point in points {
            lines.append(contentsOf: trackpoint(point))
        }

        lines.append("  </trkseg>")
        lines.append(" </trk>")
        lines.append("</gpx>")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func trackpoint(_ point: RecordingPoint) -> [String] {
        var lines: [String] = []
        lines.append("   <trkpt lat=\"\(coordinate(point.latitude))\" lon=\"\(coordinate(point.longitude))\">")
        if point.hasElevation {
            lines.append("    <ele>\(String(format: "%.1f", point.elevation))</ele>")
        }
        lines.append("    <time>\(iso8601(point.timestamp))</time>")

        // Sensor extensions are wired now but gated on the per-point `has*` flags;
        // BLE straps that set them land in S11 (#59), so today nothing is emitted.
        let tpx = trackPointExtension(point)
        if !tpx.isEmpty || point.hasPower {
            lines.append("    <extensions>")
            lines.append(contentsOf: tpx)
            if point.hasPower {
                // Strava-style <power>, sibling of TrackPointExtension (S0 §2).
                lines.append("     <power>\(number(point.power))</power>")
            }
            lines.append("    </extensions>")
        }

        lines.append("   </trkpt>")
        return lines
    }

    private static func trackPointExtension(_ point: RecordingPoint) -> [String] {
        guard point.hasHeartRate || point.hasCadence else { return [] }
        var lines: [String] = []
        lines.append("     <gpxtpx:TrackPointExtension>")
        if point.hasHeartRate {
            lines.append("      <gpxtpx:hr>\(point.heartRate)</gpxtpx:hr>")
        }
        if point.hasCadence {
            lines.append("      <gpxtpx:cad>\(number(point.cadence))</gpxtpx:cad>")
        }
        lines.append("     </gpxtpx:TrackPointExtension>")
        return lines
    }

    // MARK: - Formatting

    /// Decimal degrees with 7 dp (≈11 mm), matching the reference fixture.
    private static func coordinate(_ value: Double) -> String {
        String(format: "%.7f", value)
    }

    /// A numeric value without a trailing `.0` when whole (cadence/power).
    private static func number(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// UTC ISO-8601 with a `Z` suffix, e.g. `2026-06-25T08:00:00Z` (S0 §2).
    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
