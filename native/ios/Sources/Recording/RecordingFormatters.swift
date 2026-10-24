import CoreLocation
import Foundation

/// Shared formatting for recording stats, so the live dashboard
/// (`RecordingViewController`) and the post-stop review screen
/// (`RecordingReviewViewController`) render identical numbers.
enum RecordingFormatters {
    /// `x.xx` km from a distance in metres.
    static func distanceKilometers(_ meters: CLLocationDistance) -> String {
        String(format: "%.2f", meters / 1000)
    }

    static func speed(_ metersPerSecond: CLLocationSpeed) -> String {
        String(format: "%.1f km/h", max(metersPerSecond, 0) * 3.6)
    }

    /// `m:ss/km`. Instantaneous pace is inherently jumpy; near-zero speed reads as
    /// `—` rather than an absurd figure (smoothing is a later refinement).
    static func pace(_ metersPerSecond: CLLocationSpeed) -> String {
        guard metersPerSecond > 0.3 else { return "—" }
        let secondsPerKm = 1000 / metersPerSecond
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm.rounded()) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    /// Speed (km/h) or pace (min/km) per the sport.
    static func speedOrPace(_ metersPerSecond: CLLocationSpeed, usesPace: Bool) -> String {
        usesPace ? pace(metersPerSecond) : speed(metersPerSecond)
    }

    /// `H:MM:SS` once past an hour, else `MM:SS`.
    static let elapsed: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    /// "1 enregistrement non envoyé", "3 enregistrements non envoyés".
    static func unsentCount(_ count: Int) -> String {
        count == 1 ? "1 enregistrement non envoyé" : "\(count) enregistrements non envoyés"
    }

    /// Elapsed seconds as `H:MM:SS` / `MM:SS`, with a `00:00` fallback.
    static func elapsedString(_ interval: TimeInterval) -> String {
        elapsed.string(from: interval) ?? "00:00"
    }
}
