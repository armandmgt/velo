import CoreLocation
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
/// Two exits, now meaningfully distinct:
/// - **Fermer** (close): leaves the screen — recording keeps running in the
///   background (the controller outlives this VC) and the tab-bar Record button
///   reflects that.
/// - **Arrêter** (stop): ends and finalizes the recording (upload is S4).
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

    private lazy var startButton = makeStartButton()
    private lazy var lapButton = makeSecondaryButton(title: "Tour") { [weak self] in self?.markLap() }
    private lazy var pauseResumeButton = makeSecondaryButton(title: "Pause") { [weak self] in self?.togglePause() }
    private lazy var stopButton = makeStopButton()
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
        glyphView.tintColor = .systemRed
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
        view.addSubview(startButton)
        view.addSubview(activeControls)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            statsRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            statsRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

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

    /// End and finalize the recording.
    private func stop() {
        controller.stop()
        dismiss(animated: true)
    }

    // MARK: - Rendering

    private func render(state: RecordingController.State) {
        switch state {
        case .idle:
            glyphView.image = symbol("record.circle", pointSize: 96)
            glyphView.tintColor = .systemRed
            startButton.isHidden = false
            activeControls.isHidden = true
        case .recording:
            glyphView.image = symbol("record.circle.fill", pointSize: 96)
            glyphView.tintColor = .systemRed
            startButton.isHidden = true
            activeControls.isHidden = false
            pauseResumeButton.configuration?.title = "Pause"
        case .paused:
            glyphView.image = symbol("record.circle.fill", pointSize: 96)
            glyphView.tintColor = .systemGray
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
