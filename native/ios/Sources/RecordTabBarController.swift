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

    /// What the floating action button does, decided by the selected tab (and the
    /// live recording state). On the dashboard it records; on the other tabs it
    /// becomes a `+` that opens the matching web "new" form. A recording in
    /// progress overrides everything — the record button stays reachable (and
    /// pulsing) from every tab so an active recording still "reads as active from
    /// anywhere in the tab bar".
    private enum FabMode {
        case record
        case newActivity
        case newRoute
    }

    /// The floating action button. In record mode the `record.circle` glass capsule
    /// turns from accent-tinted to red and pulses while a recording is in progress
    /// (S3, #51); in the `+` modes it opens `/activities/new` or `/planned_routes/new`.
    private(set) lazy var recordButton: UIButton = makeRecordButton()

    /// The FAB action resolved for the current tab + recording state.
    private var fabMode: FabMode = .record

    /// Re-resolve the FAB whenever the selected tab changes programmatically
    /// (e.g. the recording-review screen jumps to the Activités tab). Tab *taps*
    /// don't route through this setter — the `UITabBarControllerDelegate`
    /// callbacks below cover those.
    override var selectedIndex: Int {
        didSet { updateFab() }
    }

    /// Re-resolves the FAB on tab *taps*, which don't route through `selectedIndex`.
    /// `HotwireTabBarController` makes itself its own `UITabBarControllerDelegate`
    /// (`delegate = self`, to `start()` the tab's navigator), and we can't override
    /// its `public` (non-`open`) delegate methods, nor call `super` on the
    /// low-level `tabBar(_:didSelect:)` (no super implementation → SIGABRT). So we
    /// interpose a forwarding delegate that runs Hotwire's callback, then ours.
    private lazy var fabTabBarDelegate = FabTabBarDelegate(forwardingTo: self) { [weak self] in
        self?.updateFab()
    }

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
        updateFab()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Install our forwarding delegate here, not in viewDidLoad: `viewDidLoad`
        // runs *inside* `HotwireTabBarController.init`, which then resets
        // `delegate = self` right after `super.init`, clobbering an earlier
        // assignment. By viewDidAppear init is long done, so this sticks. Idempotent.
        if !(delegate is FabTabBarDelegate) {
            delegate = fabTabBarDelegate
        }
        updateFab()
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
        updateFab()
    }

    /// Decide what the FAB should be right now: a live recording always wins (keep
    /// the record button reachable from every tab); otherwise the selected tab
    /// picks the mode.
    ///
    /// Resolve the tab through `activeNavigator` rather than `selectedIndex`: on
    /// iOS 18+ the tab bar is `UITab`-backed and `selectedIndex` doesn't track the
    /// selection (HotwireTabBarController itself resolves via `selectedTab` first,
    /// which is exactly what `activeNavigator` uses).
    private func resolvedFabMode() -> FabMode {
        if RecordingController.shared.isActive { return .record }
        // `viewDidLoad` (→ updateFab) runs during init, before `load(_:)` sets the
        // tabs up, and `activeNavigator` fatalErrors when no tab resolves. The
        // per-tab navigators only exist post-`load`, so their presence gates the
        // `activeNavigator` read; until then the FAB is the default Record button.
        guard let activitiesNavigator = navigator(for: .activities),
              let plannedRoutesNavigator = navigator(for: .plannedRoutes) else {
            return .record
        }
        let active = activeNavigator
        if active === activitiesNavigator { return .newActivity }
        if active === plannedRoutesNavigator { return .newRoute }
        return .record
    }

    /// Sync the FAB's glyph, colour, label and pulse to the resolved mode: a red,
    /// pulsing `record.circle` while recording; the accent-tinted `record.circle`
    /// on the dashboard; an accent-tinted `plus` on the other tabs.
    private func updateFab() {
        let mode = resolvedFabMode()
        fabMode = mode

        let isRecording = RecordingController.shared.isActive
        switch mode {
        case .record:
            recordButton.configuration?.image = fabImage("record.circle")
            recordButton.configuration?.baseBackgroundColor = isRecording ? .systemRed : .tintColor
            recordButton.accessibilityLabel = "Enregistrer"
        case .newActivity:
            recordButton.configuration?.image = fabImage("plus")
            recordButton.configuration?.baseBackgroundColor = .tintColor
            recordButton.accessibilityLabel = "Nouvelle activité"
        case .newRoute:
            recordButton.configuration?.image = fabImage("plus")
            recordButton.configuration?.baseBackgroundColor = .tintColor
            recordButton.accessibilityLabel = "Nouveau parcours"
        }

        // Only manage the pulse while on-window (see viewDidLoad). When off-window,
        // skip it — `viewDidAppear` re-applies once the button is visible again.
        guard view.window != nil else { return }
        (mode == .record && isRecording) ? startPulsing() : stopPulsing()
    }

    private func fabImage(_ systemName: String) -> UIImage? {
        UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        )
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
        // Starts as the `record.circle` outline; `updateFab()` swaps it to `plus`
        // on the non-dashboard tabs and turns the capsule red (and pulses) while
        // recording (S3).
        config.image = fabImage("record.circle")
        config.cornerStyle = .capsule

        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { [weak self] _ in self?.handleFabTap() }
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Enregistrer"
        return button
    }

    /// Route the tap to whatever the FAB currently is: present recording, or open
    /// the matching web "new" form in the active tab's navigator. `/activities/new`
    /// and `/planned_routes/new` end in `/new`, so the path config presents them
    /// modally (MODAL_PATTERNS).
    private func handleFabTap() {
        switch fabMode {
        case .record:
            presentRecording()
        case .newActivity:
            activeNavigator.route(AppConfig.baseURL.appendingPathComponent("activities/new"))
        case .newRoute:
            activeNavigator.route(AppConfig.baseURL.appendingPathComponent("planned_routes/new"))
        }
    }

    /// Present the recording review — the web `/activities/new` (#116).
    ///
    /// `isModalInPresentation` makes it terminal, the way the native screen's
    /// hidden back button did: after Arrêter the only ways out are Enregistrer
    /// and Supprimer. `RecordingReviewComponent` clears the flag when it
    /// dismisses, since the modal navigator is shared with the FAB's own modals.
    func presentRecordingReview() {
        let navigator = activeNavigator
        navigator.route(AppConfig.baseURL.appendingPathComponent("activities/new"))
        navigator.modalRootViewController.isModalInPresentation = true
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

/// Sits between `UITabBarController` and Hotwire's own delegate: it forwards the
/// `didSelect` callbacks to `HotwireTabBarController` (which `start()`s the newly
/// selected tab's navigator) and then runs `onSelect` — how `RecordTabBarController`
/// learns about tab *taps* without overriding Hotwire's non-`open` delegate methods.
/// These delegate callbacks only *notify* of a selection; the tab switch itself is
/// UIKit-internal, so forwarding here can't break navigation. iOS 18+ reports
/// selection via the `UITab` callback, earlier systems via the view-controller one.
private final class FabTabBarDelegate: NSObject, UITabBarControllerDelegate {
    private weak var forwardee: HotwireTabBarController?
    private let onSelect: () -> Void

    init(forwardingTo forwardee: HotwireTabBarController, onSelect: @escaping () -> Void) {
        self.forwardee = forwardee
        self.onSelect = onSelect
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        forwardee?.tabBarController(tabBarController, didSelect: viewController)
        onSelect()
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        forwardee?.tabBarController(tabBarController, didSelectTab: selectedTab, previousTab: previousTab)
        onSelect()
    }
}
