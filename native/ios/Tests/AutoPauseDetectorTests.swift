import CoreLocation
import Testing
@testable import Velo

/// The pause automatique rules from ADR 0002: enter after ten still seconds,
/// leave on fifteen metres of displacement, and never override an explicit
/// instruction from the rider.
@Suite("AutoPauseDetector")
struct AutoPauseDetectorTests {
    private static let origin = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)

    /// A fix `seconds` into the recording, `metresNorth` from the origin.
    private func fix(at seconds: TimeInterval, speed: CLLocationSpeed, metresNorth: CLLocationDistance = 0) -> CLLocation {
        let coordinate = CLLocationCoordinate2D(
            latitude: Self.origin.latitude + metresNorth / 111_320,
            longitude: Self.origin.longitude
        )
        return CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: speed,
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    private func armedDetector() -> AutoPauseDetector {
        var detector = AutoPauseDetector(isEnabled: true)
        detector.reset()
        return detector
    }

    @Test("a moving rider is never auto-paused")
    func movingNeverPauses() {
        var detector = armedDetector()
        for second in 0...30 {
            let outcome = detector.consider(fix(at: TimeInterval(second), speed: 5, metresNorth: Double(second) * 5))
            #expect(outcome == .none)
        }
    }

    @Test("ten still seconds trigger a pause, and not a second sooner")
    func stillnessPauses() {
        var detector = armedDetector()
        for second in 0..<10 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1)) == .none)
        }
        #expect(detector.consider(fix(at: 10, speed: 0.1)) == .shouldAutoPause)
    }

    @Test("a fix at the moving threshold counts as moving")
    func thresholdCountsAsMoving() {
        var detector = armedDetector()
        for second in 0...30 {
            let outcome = detector.consider(fix(at: TimeInterval(second), speed: AutoPauseDetector.stillSpeedThreshold))
            #expect(outcome == .none)
        }
    }

    @Test("any movement restarts the still run")
    func movementResetsTheRun() {
        var detector = armedDetector()
        for second in 0..<9 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1)) == .none)
        }
        #expect(detector.consider(fix(at: 9, speed: 3)) == .none)
        // The run restarts at second 10, so the pause is due at second 20 — the
        // nine still seconds already banked before the movement do not count.
        for second in 10..<20 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1)) == .none)
        }
        #expect(detector.consider(fix(at: 20, speed: 0.1)) == .shouldAutoPause)
    }

    @Test("resume needs fifteen metres, not a speed reading")
    func resumeOnDisplacement() {
        var detector = armedDetector()
        for second in 0...10 { _ = detector.consider(fix(at: TimeInterval(second), speed: 0.1)) }
        // Doppler noise while stationary must not resume, however fast it reads.
        #expect(detector.consider(fix(at: 11, speed: 4, metresNorth: 3)) == .none)
        #expect(detector.consider(fix(at: 12, speed: 0, metresNorth: 14)) == .none)
        #expect(detector.consider(fix(at: 13, speed: 0, metresNorth: 20)) == .shouldAutoResume)
    }

    @Test("a manual resume disarms the detector until the rider actually moves")
    func manualResumeSuppresses() {
        var detector = armedDetector()
        for second in 0...10 { _ = detector.consider(fix(at: TimeInterval(second), speed: 0.1)) }
        detector.userDidResume()

        // Still stationary, but the rider just said "record me" — leave them alone.
        for second in 11...40 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1)) == .none)
        }
        // Once they've genuinely moved, the detector re-arms.
        #expect(detector.consider(fix(at: 41, speed: 3, metresNorth: 20)) == .none)
        for second in 42..<52 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1, metresNorth: 20)) == .none)
        }
        #expect(detector.consider(fix(at: 52, speed: 0.1, metresNorth: 20)) == .shouldAutoPause)
    }

    @Test("a manual pause takes the detector out of play entirely")
    func manualPauseSilencesTheDetector() {
        var detector = armedDetector()
        detector.userDidPause()
        for second in 0...30 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1)) == .none)
        }
        // Movement must not auto-resume a pause the rider asked for.
        #expect(detector.consider(fix(at: 31, speed: 5, metresNorth: 500)) == .none)
    }

    @Test("an unmeasurable speed is not evidence of stillness")
    func invalidSpeedIsNotStillness() {
        var detector = armedDetector()
        // CoreLocation reports -1 when it cannot measure speed — common while the
        // fix is still settling. Pausing on that would stop a moving rider.
        for second in 0...30 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: -1)) == .none)
        }
    }

    @Test("an unmeasurable speed breaks a still run rather than extending it")
    func invalidSpeedBreaksTheRun() {
        var detector = armedDetector()
        for second in 0..<9 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0.1)) == .none)
        }
        #expect(detector.consider(fix(at: 9, speed: -1)) == .none)
        #expect(detector.consider(fix(at: 10, speed: 0.1)) == .none)
    }

    @Test("a disabled detector never fires")
    func disabledNeverFires() {
        var detector = AutoPauseDetector(isEnabled: false)
        detector.reset()
        for second in 0...30 {
            #expect(detector.consider(fix(at: TimeInterval(second), speed: 0)) == .none)
        }
    }
}
