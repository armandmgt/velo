import HotwireNative
import UIKit

/// The authenticated tab-bar root, extended with a native **Record** entry point
/// (#41, S1).
///
/// The three tabs stay web-backed Hotwire navigators; recording, however, needs
/// native UIKit (GPS, sensors, an animated indicator), so the entry point is a
/// `UIButton` *we own* — not a system tab item. Owning the view matters: S2+
/// will animate it (e.g. blink while a recording is in progress), which system
/// `UITab`/`UISearchTab` items don't allow since they don't expose their view.
///
/// The button floats just *above* the tab bar, right-aligned, kept understated.
/// Floating above (rather than inside the bar's trailing edge) avoids fighting
/// the iOS 26 glass tab-bar internals and pins cleanly with Auto Layout.
final class RecordTabBarController: HotwireTabBarController {
    private static let buttonSize: CGFloat = 56

    /// The floating Record entry point. While a recording is in progress (S3, #51)
    /// its symbol switches from `record.circle` to `record.circle.fill` tinted red
    /// and pulses, so the recording reads as active from anywhere in the tab bar.
    private(set) lazy var recordButton: UIButton = makeRecordButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        addRecordButton()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingStateDidChange),
            name: .recordingStateDidChange,
            object: nil
        )
        // Reflect any recording already in progress (also primes kill recovery).
        updateRecordButton()
    }

    @objc private func recordingStateDidChange() {
        updateRecordButton()
    }

    /// Mirror the controller's active/idle state onto the button: red filled +
    /// pulsing while recording, the understated outline when idle.
    private func updateRecordButton() {
        let isActive = RecordingController.shared.isActive
        let symbol = isActive ? "record.circle.fill" : "record.circle"
        recordButton.configuration?.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        )
        recordButton.configuration?.baseForegroundColor = isActive ? .systemRed : .white
        isActive ? startPulsing() : stopPulsing()
    }

    private static let pulseKey = "recordingPulse"

    private func startPulsing() {
        guard recordButton.layer.animation(forKey: Self.pulseKey) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        recordButton.layer.add(pulse, forKey: Self.pulseKey)
    }

    private func stopPulsing() {
        recordButton.layer.removeAnimation(forKey: Self.pulseKey)
    }

    private func addRecordButton() {
        view.addSubview(recordButton)

        // Float the button just above the bottom tab bar on iPhone. On iPad with
        // iOS 18+/26 the tab bar is the floating *top* pill and is NOT a
        // descendant of our view, so pinning to `tabBar.topAnchor` there throws
        // an Auto Layout "no common ancestor" exception — a crash on sign-in.
        // Fall back to the safe-area bottom whenever the tab bar isn't in our
        // hierarchy (no bottom bar to clear there anyway).
        let bottomAnchor = tabBar.isDescendant(of: view)
            ? tabBar.topAnchor
            : view.safeAreaLayoutGuide.bottomAnchor

        NSLayoutConstraint.activate([
            recordButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            recordButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            recordButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            recordButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    private func makeRecordButton() -> UIButton {
        // Tinted Liquid Glass on iOS 26 — `prominentGlass` reads as a coloured
        // glass (visible against content) while keeping the material; the glass
        // supplies its own depth, so no manual shadow. Filled capsule fallback.
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .prominentGlass()
        } else {
            config = .filled()
        }
        config.baseBackgroundColor = .tintColor
        config.baseForegroundColor = .white
        // Idle look: a small `record.circle` outline. `updateRecordButton()` swaps
        // to `record.circle.fill` tinted red (and pulses) while recording (S3).
        config.image = UIImage(
            systemName: "record.circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        )
        config.cornerStyle = .capsule

        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { [weak self] _ in self?.presentRecording() }
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Enregistrer"
        return button
    }

    /// Present the recording screen full-screen. `.fullScreen` has no pull-down
    /// dismiss gesture, and `isModalInPresentation` blocks it on any style — the
    /// screen is closeable only via its explicit Fermer/Arrêter buttons, so a
    /// recording can't be dismissed by accident.
    private func presentRecording() {
        let navigationController = UINavigationController(rootViewController: RecordingViewController())
        navigationController.modalPresentationStyle = .fullScreen
        navigationController.isModalInPresentation = true
        present(navigationController, animated: true)
    }
}
