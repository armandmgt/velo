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
    /// the `record.circle` glass capsule turns from accent-tinted to red and pulses,
    /// so the recording reads as active from anywhere in the tab bar.
    private(set) lazy var recordButton: UIButton = makeRecordButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        addRecordButton()
        configureSelectedTabColor()
        // Re-resolve the selected-tab accent when the app switches light/dark.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.configureSelectedTabColor()
        }
        // Recording always starts/stops behind the full-screen recording modal,
        // i.e. while this controller is off-window. Touching the pulse animation
        // there is both pointless (the button is hidden) and broken: a CAAnimation
        // added to an off-window layer escapes `animationKeys()` once the glass
        // configuration re-renders, so it can never be removed and outlives Stop.
        // So we drive the pulse purely from `viewDidAppear` — which fires when the
        // modal dismisses — plus app-foreground (CoreAnimation strips animations on
        // backgrounding). The notification only refreshes the colour off-window.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncRecordButton),
            name: .recordingStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncRecordButton),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        applyRecordButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyRecordButtonState()
    }

    /// Accent matching the web app's `--color-primary` (see AccentColor asset).
    private static let accentOrange = UIColor(red: 0.982, green: 0.591, blue: 0.000, alpha: 1)
    private static let accentBlue = UIColor(red: 0.165, green: 0.494, blue: 1.000, alpha: 1)

    /// Pin the *selected* tab item to the app accent (orange light / blue dark) so
    /// it matches the rest of the chrome.
    ///
    /// iOS 26's glass selected-tab pill resolves dynamic colours against a fixed
    /// (light) trait, so a normal dynamic accent renders the same hue in both modes
    /// there (it showed orange even in dark). So we resolve the accent ourselves
    /// from the controller's actual appearance and hand the tab bar a plain colour,
    /// re-running whenever the appearance changes.
    private func configureSelectedTabColor() {
        let color = traitCollection.userInterfaceStyle == .dark ? Self.accentBlue : Self.accentOrange
        let appearance = tabBar.standardAppearance.copy()
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.selected.iconColor = color
            layout.selected.titleTextAttributes = [.foregroundColor: color]
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    @objc private func syncRecordButton() {
        applyRecordButtonState()
    }

    /// Mirror the controller's active/idle state onto the button: a red, pulsing
    /// glass capsule while recording; the accent-tinted capsule when idle. The
    /// `record.circle` symbol is unchanged between states.
    private func applyRecordButtonState() {
        let isActive = RecordingController.shared.isActive
        recordButton.configuration?.baseBackgroundColor = isActive ? .systemRed : .tintColor
        // Only manage the pulse while on-window (see viewDidLoad). When off-window,
        // skip it — `viewDidAppear` re-applies once the button is visible again.
        guard view.window != nil else { return }
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
        recordButton.layer.opacity = 1
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
        // A small `record.circle` outline in both states; `updateRecordButton()`
        // turns the capsule red (and pulses) while recording (S3).
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
