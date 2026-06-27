import CoreLocation
import HotwireNative
import UIKit

/// The native recording surface (#41).
///
/// S1 (#49) was a static skeleton; S2 (#50) wired the live GPS feed. S3 (#51)
/// makes it statful and durable: it drives the long-lived `RecordingController`
/// (which owns the GPS pipe + the Core Data store) rather than holding the
/// recorder itself, and shows live stats — elapsed, distance, current/avg speed.
///
/// Flow (explicit start): opening the screen *arms* the GPS for readiness
/// ("GPS prêt") but does **not** record. **Démarrer** starts; then
/// **Pause/Reprendre** and **Tour** (a lap marker) drive what's recorded.
///
/// A sport is chosen up front via a native picker (S4 — #52), defaulting to the
/// last-used sport.
///
/// The design (#…) puts the **stats** at the centre — they're the main payload
/// until a live map lands. GPS signal quality is intentionally minor: a slim
/// colour-coded banner pinned at the top. State (recording/paused) reads from a
/// small pill above the stats.
///
/// Two exits, now meaningfully distinct:
/// - **Fermer** (close): leaves the screen — recording keeps running in the
///   background (the controller outlives this VC) and the tab-bar Record button
///   reflects that.
/// - **Arrêter** (stop): ends and finalizes the recording, then serializes it to
///   GPX and uploads it (S4 — #52). On success the webview jumps to the new
///   activity; on failure the recording is kept and a retry is offered.
final class RecordingViewController: UIViewController {
    private var controller: RecordingController { .shared }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Enregistrement"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Fermer",
            primaryAction: UIAction { [weak self] _ in self?.close() }
        )

        setupLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        controller.delegate = self
        // Reflect whatever the controller is already doing — the screen may have
        // been reopened onto an in-progress (or paused) recording.
        updateSportButton()
        render(state: controller.state)
        render(stats: controller.currentStats)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Arm the GPS for readiness (and request permission on first run) — but do
        // NOT start recording; that waits for an explicit Démarrer.
        controller.arm()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Leave GPS running only if a recording is in progress; otherwise stop the
        // readiness stream so an opened-then-closed screen doesn't drain battery.
        controller.disarmIfIdle()
    }

    // MARK: - Layout

    private let gpsBanner = GPSBannerView()
    private let statePill = StatusPillView()
    private let elapsedLabel = UILabel()
    private let elapsedCaption = UILabel()
    private let distanceStat = StatView(caption: "Distance")
    private let speedStat = StatView(caption: "Vitesse")
    private let avgStat = StatView(caption: "Moyenne")

    private lazy var sportButton = makeSportButton()
    private lazy var startButton = makeStartButton()
    private lazy var lapButton = makeSecondaryButton(title: "Tour") { [weak self] in self?.markLap() }
    private lazy var pauseResumeButton = makeSecondaryButton(title: "Pause") { [weak self] in self?.togglePause() }
    private lazy var stopButton = makeStopButton()

    /// Shown while the recording is being serialized + uploaded after Arrêter.
    private let uploadingSpinner = UIActivityIndicatorView(style: .medium)
    private lazy var uploadingStack: UIStackView = {
        let label = UILabel()
        label.text = "Envoi en cours…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [uploadingSpinner, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()
    private var isUploading = false

    private lazy var activeControls: UIStackView = {
        let row = UIStackView(arrangedSubviews: [lapButton, pauseResumeButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        let stack = UIStackView(arrangedSubviews: [row, stopButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private func setupLayout() {
        // Tapping the banner when access is denied jumps to Settings.
        gpsBanner.onTapWhenDenied = {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
        gpsBanner.translatesAutoresizingMaskIntoConstraints = false

        // The hero: a big elapsed clock over a generous stats grid.
        elapsedLabel.text = "00:00"
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 60, weight: .semibold)
        elapsedLabel.textColor = .label
        elapsedLabel.textAlignment = .center

        elapsedCaption.text = "temps"
        elapsedCaption.font = .preferredFont(forTextStyle: .caption1)
        elapsedCaption.textColor = .secondaryLabel
        elapsedCaption.textAlignment = .center

        let statsRow = UIStackView(arrangedSubviews: [distanceStat, speedStat, avgStat])
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 8

        let elapsedBlock = UIStackView(arrangedSubviews: [elapsedLabel, elapsedCaption])
        elapsedBlock.axis = .vertical
        elapsedBlock.alignment = .center
        elapsedBlock.spacing = 0

        let centre = UIStackView(arrangedSubviews: [statePill, elapsedBlock, statsRow])
        centre.axis = .vertical
        centre.alignment = .center
        centre.spacing = 28
        centre.setCustomSpacing(32, after: elapsedBlock)
        centre.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(gpsBanner)
        view.addSubview(centre)
        view.addSubview(sportButton)
        view.addSubview(startButton)
        view.addSubview(activeControls)
        view.addSubview(uploadingStack)

        NSLayoutConstraint.activate([
            // Slim GPS banner pinned at the very top, low emphasis.
            gpsBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            gpsBanner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            gpsBanner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            // Stats block owns the centre of the screen.
            centre.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centre.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            centre.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            centre.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            statsRow.leadingAnchor.constraint(equalTo: centre.leadingAnchor),
            statsRow.trailingAnchor.constraint(equalTo: centre.trailingAnchor),

            // Sport picker sits just above Démarrer (both visible only while idle).
            sportButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            sportButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            sportButton.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -12),
            sportButton.heightAnchor.constraint(equalToConstant: 50),

            uploadingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadingStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),

            startButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            startButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            startButton.heightAnchor.constraint(equalToConstant: 54),

            activeControls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            activeControls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            activeControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            lapButton.heightAnchor.constraint(equalToConstant: 54),
            pauseResumeButton.heightAnchor.constraint(equalToConstant: 54),
            stopButton.heightAnchor.constraint(equalToConstant: 54),
        ])
    }

    // MARK: - Buttons

    /// A pull-down sport picker (UIMenu). The chosen sport lives on the
    /// controller; `updateSportButton()` keeps the title/glyph and the menu's
    /// checkmark in sync.
    private func makeSportButton() -> UIButton {
        let button = glassButton(prominent: false)
        button.configuration?.imagePadding = 8
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "sportPicker"
        return button
    }

    private func updateSportButton() {
        let sport = controller.sport
        sportButton.configuration?.title = sport.displayName
        sportButton.configuration?.image = UIImage(systemName: sport.symbolName)
        sportButton.menu = makeSportMenu()
        // Speed↔pace caption follows the sport; refresh the live values too.
        updateMetricCaptions()
        render(stats: controller.currentStats)
    }

    private func updateMetricCaptions() {
        speedStat.caption = controller.sport.usesPace ? "Allure" : "Vitesse"
    }

    private func makeSportMenu() -> UIMenu {
        let current = controller.sport
        let actions = Sport.allCases.map { sport in
            UIAction(
                title: sport.displayName,
                image: UIImage(systemName: sport.symbolName),
                state: sport == current ? .on : .off
            ) { [weak self] _ in
                self?.controller.sport = sport
                self?.updateSportButton()
            }
        }
        return UIMenu(title: "Sport", children: actions)
    }

    private func makeStartButton() -> UIButton {
        let button = glassButton(prominent: true, tint: .systemGreen)
        button.configuration?.title = "Démarrer"
        button.addAction(UIAction { [weak self] _ in self?.controller.start() }, for: .primaryActionTriggered)
        return button
    }

    private func makeStopButton() -> UIButton {
        let button = glassButton(prominent: true, tint: .systemRed)
        button.configuration?.title = "Arrêter"
        button.addAction(UIAction { [weak self] _ in self?.stop() }, for: .primaryActionTriggered)
        return button
    }

    private func makeSecondaryButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = glassButton(prominent: false)
        button.configuration?.title = title
        button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        return button
    }

    /// A Liquid Glass button, matching the tab-bar Record button's treatment
    /// (`RecordTabBarController.makeRecordButton`): `prominentGlass` (tinted,
    /// reads against content) for primary colour actions, plain `glass` for
    /// secondary ones, with a filled/tinted fallback below iOS 26.
    private func glassButton(prominent: Bool, tint: UIColor? = nil) -> UIButton {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = prominent ? .prominentGlass() : .glass()
        } else {
            config = prominent ? .filled() : .tinted()
        }
        if let tint {
            config.baseBackgroundColor = tint
            config.baseForegroundColor = .white
        }
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Actions

    private func togglePause() {
        controller.state == .recording ? controller.pause() : controller.resume()
    }

    private func markLap() {
        controller.markLap()
    }

    /// Leave the screen; recording continues in the background.
    private func close() {
        dismiss(animated: true)
    }

    /// End the recording, then serialize + upload it (S4 — #52).
    private func stop() {
        guard let session = controller.stop() else {
            dismiss(animated: true)
            return
        }
        // A stop with no fixes recorded has nothing to upload — drop it and leave.
        guard !session.orderedPoints.isEmpty else {
            controller.discard(session)
            dismiss(animated: true)
            return
        }
        upload(session)
    }

    /// Serialize the finalized session to GPX and POST it. On success the local
    /// session is cleared and the webview jumps to the new activity; on failure
    /// the recording is kept (still in Core Data) and a retry is offered.
    private func upload(_ session: RecordingSession) {
        enterUploadingState()
        let sport = controller.sport
        let gpx = RecordingGPXEncoder.gpx(for: session, sport: sport)
        ActivityUploader.upload(gpx: gpx, sport: sport, name: nil) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.controller.discard(session)
                self.navigateToActivity(url)
            case .failure(let error):
                self.exitUploadingState()
                self.presentUploadFailure(error, session: session)
            }
        }
    }

    /// Push the created activity onto the Activités tab, then dismiss the modal
    /// to reveal it. Mirrors `NotificationCountComponent`'s tab-bar reach.
    private func navigateToActivity(_ url: URL) {
        if let tabBar = view.window?.rootViewController as? HotwireTabBarController {
            tabBar.selectedIndex = 1 // Activités
            tabBar.activeNavigator.route(url)
        }
        dismiss(animated: true)
    }

    private func presentUploadFailure(_ error: ActivityUploader.UploadError, session: RecordingSession) {
        let message: String
        switch error {
        case .validation(let errors):
            message = errors.joined(separator: "\n")
        case .network:
            message = "L'enregistrement a été conservé. Vérifiez votre connexion, puis réessayez."
        }
        let alert = UIAlertController(title: "Envoi échoué", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Réessayer", style: .default) { [weak self] _ in
            self?.upload(session)
        })
        alert.addAction(UIAlertAction(title: "Plus tard", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func enterUploadingState() {
        isUploading = true
        sportButton.isHidden = true
        startButton.isHidden = true
        activeControls.isHidden = true
        uploadingStack.isHidden = false
        uploadingSpinner.startAnimating()
        // Block Fermer mid-upload so the modal can't be torn down under the request.
        navigationItem.leftBarButtonItem?.isEnabled = false
    }

    private func exitUploadingState() {
        isUploading = false
        uploadingSpinner.stopAnimating()
        uploadingStack.isHidden = true
        navigationItem.leftBarButtonItem?.isEnabled = true
        // The controller is idle after stop(); restore the idle controls.
        render(state: controller.state)
    }

    // MARK: - Rendering

    private func render(state: RecordingController.State) {
        // While uploading, the uploading UI owns the control area — don't let a
        // state callback (the `.idle` transition stop() fires) unhide the buttons.
        guard !isUploading else { return }

        // The sport picker only makes sense before a recording starts; state reads
        // from the pill above the stats.
        switch state {
        case .idle:
            statePill.set(.idle)
            sportButton.isHidden = false
            startButton.isHidden = false
            activeControls.isHidden = true
        case .recording:
            statePill.set(.recording)
            sportButton.isHidden = true
            startButton.isHidden = true
            activeControls.isHidden = false
            pauseResumeButton.configuration?.title = "Pause"
        case .paused:
            statePill.set(.paused)
            sportButton.isHidden = true
            startButton.isHidden = true
            activeControls.isHidden = false
            pauseResumeButton.configuration?.title = "Reprendre"
        }
    }

    private func render(stats: RecordingStats) {
        let usesPace = controller.sport.usesPace
        elapsedLabel.text = Self.elapsedFormatter.string(from: stats.elapsed) ?? "00:00"
        distanceStat.value = String(format: "%.2f km", stats.distance / 1000)
        speedStat.value = usesPace ? Self.paceString(stats.currentSpeed) : Self.speedString(stats.currentSpeed)
        avgStat.value = usesPace ? Self.paceString(stats.averageSpeed) : Self.speedString(stats.averageSpeed)
    }

    private static func speedString(_ metersPerSecond: CLLocationSpeed) -> String {
        String(format: "%.1f km/h", max(metersPerSecond, 0) * 3.6)
    }

    /// `m:ss/km`. Instantaneous pace is inherently jumpy; near-zero speed reads as
    /// `—` rather than an absurd figure (smoothing is a later refinement).
    private static func paceString(_ metersPerSecond: CLLocationSpeed) -> String {
        guard metersPerSecond > 0.3 else { return "—" }
        let secondsPerKm = 1000 / metersPerSecond
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm.rounded()) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    /// `H:MM:SS` once past an hour, else `MM:SS`.
    private static let elapsedFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

// MARK: - RecordingControllerDelegate

extension RecordingViewController: RecordingControllerDelegate {
    func recordingController(_ controller: RecordingController, didChangeAuthorization status: LocationRecorder.Status) {
        switch status {
        case .denied:
            gpsBanner.setDenied()
            startButton.isEnabled = false
        case .authorized:
            // start() re-fires `.authorized` on every recording start — only
            // recover from a denied banner, never clobber an acquired signal.
            gpsBanner.clearDenied()
            startButton.isEnabled = true
        case .notDetermined:
            break
        }
    }

    func recordingController(_ controller: RecordingController, didChangeState state: RecordingController.State) {
        render(state: state)
    }

    func recordingController(_ controller: RecordingController, didUpdate stats: RecordingStats) {
        render(stats: stats)
    }

    func recordingController(_ controller: RecordingController, didReceiveFix location: CLLocation, pointCount: Int) {
        gpsBanner.update(horizontalAccuracy: location.horizontalAccuracy)
    }
}

// MARK: - StatView

/// A value-over-caption stat cell used in the live stats grid — the screen's
/// main payload, so the value is large.
private final class StatView: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    var value: String {
        get { valueLabel.text ?? "" }
        set { valueLabel.text = newValue }
    }

    var caption: String {
        get { captionLabel.text ?? "" }
        set { captionLabel.text = newValue }
    }

    init(caption: String) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        valueLabel.text = "—"
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6

        captionLabel.font = .preferredFont(forTextStyle: .caption1)
        captionLabel.textColor = .secondaryLabel
        captionLabel.textAlignment = .center
        captionLabel.text = caption

        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - StatusPillView

/// A small, secondary state indicator (dot + word) above the stats. Pulses while
/// recording. Hidden when idle so it doesn't compete with the stats.
private final class StatusPillView: UIView {
    enum State { case idle, recording, paused }

    private let dot = UIView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer.cornerRadius = 5

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(_ state: State) {
        switch state {
        case .idle:
            isHidden = true
            stopPulsing()
        case .recording:
            isHidden = false
            dot.backgroundColor = .systemRed
            label.text = "Enregistrement"
            startPulsing()
        case .paused:
            isHidden = false
            dot.backgroundColor = .systemOrange
            label.text = "En pause"
            stopPulsing()
        }
    }

    private func startPulsing() {
        guard dot.layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer.add(pulse, forKey: "pulse")
    }

    private func stopPulsing() {
        dot.layer.removeAnimation(forKey: "pulse")
    }
}

// MARK: - GPSBannerView

/// A slim, colour-coded GPS-signal banner pinned at the top. Deliberately minor —
/// the stats are the screen's focus — but it surfaces signal quality and the
/// access-denied state (tap to open Settings).
private final class GPSBannerView: UIView {
    /// Invoked when the banner is tapped while access is denied.
    var onTapWhenDenied: (() -> Void)?
    private var isDenied = false

    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        setSearching()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap() {
        guard isDenied else { return }
        onTapWhenDenied?()
    }

    func setSearching() {
        isDenied = false
        apply(text: "Recherche du GPS…", color: .secondaryLabel)
    }

    func setDenied() {
        isDenied = true
        apply(text: "Position refusée — Réglages", color: .systemRed)
    }

    /// Recover from the denied state (e.g. access granted in Settings). No-op when
    /// not denied, so an already-acquired signal isn't reset to "searching".
    func clearDenied() {
        guard isDenied else { return }
        setSearching()
    }

    func update(horizontalAccuracy: CLLocationDistance) {
        guard !isDenied else { return }
        let (text, color): (String, UIColor)
        switch horizontalAccuracy {
        case ..<0: (text, color) = ("Recherche du GPS…", .secondaryLabel) // invalid fix
        case ..<8: (text, color) = ("GPS bon", .systemGreen)
        case ..<20: (text, color) = ("GPS correct", .systemGreen)
        case ..<50: (text, color) = ("GPS moyen", .systemOrange)
        default: (text, color) = ("GPS faible", .systemOrange)
        }
        apply(text: text, color: color)
    }

    private func apply(text: String, color: UIColor) {
        label.text = text
        label.textColor = color
        backgroundColor = color.withAlphaComponent(0.15)
    }
}
