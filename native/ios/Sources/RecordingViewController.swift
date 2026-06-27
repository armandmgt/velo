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

    private let glyphView = UIImageView()
    private let elapsedLabel = UILabel()
    private let distanceStat = StatView(caption: "Distance")
    private let speedStat = StatView(caption: "Vitesse")
    private let avgStat = StatView(caption: "Moyenne")
    private let readoutLabel = UILabel()
    private let countLabel = UILabel()
    private lazy var settingsButton: UIButton = makeSettingsButton()

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
        glyphView.image = symbol("record.circle", pointSize: 96)
        glyphView.tintColor = .systemGray
        glyphView.contentMode = .scaleAspectFit

        elapsedLabel.text = "00:00"
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .semibold)
        elapsedLabel.textColor = .label

        let statsRow = UIStackView(arrangedSubviews: [distanceStat, speedStat, avgStat])
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 8

        // Debug readout (kept from S2): live lat/lon + accuracy, point count below.
        readoutLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        readoutLabel.textColor = .secondaryLabel
        readoutLabel.numberOfLines = 0
        readoutLabel.textAlignment = .center
        readoutLabel.text = "En attente du GPS…"

        countLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.isHidden = true

        settingsButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [glyphView, elapsedLabel, statsRow, readoutLabel, countLabel, settingsButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: elapsedLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(sportButton)
        view.addSubview(startButton)
        view.addSubview(activeControls)
        view.addSubview(uploadingStack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            statsRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            statsRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

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
        var config = UIButton.Configuration.tinted()
        config.cornerStyle = .large
        config.imagePadding = 8
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "sportPicker"
        return button
    }

    private func updateSportButton() {
        let sport = controller.sport
        sportButton.configuration?.title = sport.displayName
        sportButton.configuration?.image = UIImage(systemName: sport.symbolName)
        sportButton.menu = makeSportMenu()
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
        var config = UIButton.Configuration.filled()
        config.title = "Démarrer"
        config.baseBackgroundColor = .systemGreen
        config.cornerStyle = .large
        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { [weak self] _ in self?.controller.start() }
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeStopButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = "Arrêter"
        config.baseBackgroundColor = .systemRed
        config.cornerStyle = .large
        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { [weak self] _ in self?.stop() }
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeSecondaryButton(title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.cornerStyle = .large
        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { _ in action() }
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeSettingsButton() -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = "Ouvrir les Réglages"
        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Actions

    private func togglePause() {
        controller.state == .recording ? controller.pause() : controller.resume()
    }

    private func markLap() {
        controller.markLap()
        countLabel.text = "Tour \(controller.currentLap) · \(controller.pointCount) points"
        countLabel.isHidden = false
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

        // Same `record.circle` outline throughout; state reads from the tint.
        // The sport picker only makes sense before a recording starts.
        switch state {
        case .idle:
            glyphView.tintColor = .systemGray
            sportButton.isHidden = false
            startButton.isHidden = false
            activeControls.isHidden = true
        case .recording:
            glyphView.tintColor = .systemRed
            sportButton.isHidden = true
            startButton.isHidden = true
            activeControls.isHidden = false
            pauseResumeButton.configuration?.title = "Pause"
        case .paused:
            glyphView.tintColor = .systemOrange
            sportButton.isHidden = true
            startButton.isHidden = true
            activeControls.isHidden = false
            pauseResumeButton.configuration?.title = "Reprendre"
        }
    }

    private func render(stats: RecordingStats) {
        elapsedLabel.text = Self.elapsedFormatter.string(from: stats.elapsed) ?? "00:00"
        distanceStat.value = String(format: "%.2f km", stats.distance / 1000)
        speedStat.value = String(format: "%.1f km/h", stats.currentSpeed * 3.6)
        avgStat.value = String(format: "%.1f km/h", stats.averageSpeed * 3.6)
    }

    private func symbol(_ name: String, pointSize: CGFloat) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
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
            readoutLabel.textColor = .systemRed
            readoutLabel.text = "Accès à la position refusé.\nActivez-le dans les Réglages pour enregistrer."
            countLabel.isHidden = true
            settingsButton.isHidden = false
            startButton.isEnabled = false
        case .authorized:
            readoutLabel.textColor = .secondaryLabel
            if readoutLabel.text == "En attente du GPS…" { readoutLabel.text = "GPS prêt" }
            settingsButton.isHidden = true
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
        let coordinate = location.coordinate
        readoutLabel.textColor = .secondaryLabel
        readoutLabel.text = String(
            format: "lat %.6f   lon %.6f   ± %.0f m",
            coordinate.latitude,
            coordinate.longitude,
            location.horizontalAccuracy
        )
        // Only meaningful while recording; the count is pluralized unconditionally
        // to keep the maestro `[0-9]+ points` assertion stable.
        if controller.isActive {
            countLabel.text = "\(pointCount) points"
            countLabel.isHidden = false
        }
    }
}

// MARK: - StatView

/// A small value-over-caption stat cell used in the live stats row.
private final class StatView: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    var value: String {
        get { valueLabel.text ?? "" }
        set { valueLabel.text = newValue }
    }

    init(caption: String) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        valueLabel.text = "—"
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        captionLabel.font = .preferredFont(forTextStyle: .caption2)
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
