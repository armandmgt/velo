import CoreLocation
import UIKit

/// The native recording surface (#41).
///
/// S1 (#49) was a static skeleton. S2 (#50) wires the live GPS feed: a
/// `LocationRecorder` streams positions while this screen is up — including while
/// the app is backgrounded — and a debug readout shows the latest fix and the
/// running point count. Persistence, live stats (distance/speed/elapsed) and the
/// GPX upload come in S3–S4 (#51/#52); for now nothing is stored.
///
/// Two exits, distinct on purpose for later:
/// - **Fermer** (close): will simply leave the screen — recording keeps running
///   in the background and the tab-bar Record button reflects that (S3).
/// - **Arrêter** (stop): will end and finalize the recording (S4).
///
/// The recording state still lives in this VC, so S2 stops the feed on both
/// exits; S3 lifts `LocationRecorder` to a longer-lived owner so "Fermer" can
/// leave the screen without stopping the recording.
final class RecordingViewController: UIViewController {
    private let recorder = LocationRecorder()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Enregistrement"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Fermer",
            primaryAction: UIAction { [weak self] _ in self?.close() }
        )

        setupLayout()
        recorder.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Opening the screen *is* starting a recording for now (start/pause is
        // S3). Kick off after appearing so the permission alert lands on a fully
        // presented view.
        recorder.start()
    }

    // MARK: - Layout

    private let readoutLabel = UILabel()
    private let countLabel = UILabel()
    private lazy var settingsButton: UIButton = makeSettingsButton()

    private func setupLayout() {
        let glyph = UIImageView(
            image: UIImage(
                systemName: "record.circle",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 96, weight: .regular)
            )
        )
        glyph.tintColor = .systemRed
        glyph.contentMode = .scaleAspectFit

        let elapsed = UILabel()
        elapsed.text = "00:00"
        elapsed.font = .monospacedDigitSystemFont(ofSize: 48, weight: .semibold)
        elapsed.textColor = .label

        // Debug readout (S2): live lat/lon + horizontal accuracy on one label,
        // the running point count on its own single-line label below. Monospaced,
        // styled as a debug surface, not final UI.
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

        let stack = UIStackView(arrangedSubviews: [glyph, elapsed, readoutLabel, countLabel, settingsButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let stopButton = makeStopButton()

        view.addSubview(stack)
        view.addSubview(stopButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            stopButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stopButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stopButton.heightAnchor.constraint(equalToConstant: 54),
        ])
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

    /// S1: leave the screen. S3+: keep recording in the background.
    private func close() {
        recorder.stop()
        dismiss(animated: true)
    }

    /// S1: leave the screen. S4+: end, finalize, and upload the recording.
    private func stop() {
        recorder.stop()
        dismiss(animated: true)
    }
}

// MARK: - LocationRecorderDelegate

extension RecordingViewController: LocationRecorderDelegate {
    func locationRecorder(_ recorder: LocationRecorder, didChange status: LocationRecorder.Status) {
        switch status {
        case .denied:
            readoutLabel.textColor = .systemRed
            readoutLabel.text = "Accès à la position refusé.\nActivez-le dans les Réglages pour enregistrer."
            countLabel.isHidden = true
            settingsButton.isHidden = false
        case .authorized:
            readoutLabel.textColor = .secondaryLabel
            settingsButton.isHidden = true
        case .notDetermined:
            break
        }
    }

    func locationRecorder(_ recorder: LocationRecorder, didUpdate location: CLLocation, pointCount: Int) {
        let coordinate = location.coordinate
        readoutLabel.textColor = .secondaryLabel
        readoutLabel.text = String(
            format: "lat %.6f   lon %.6f   ± %.0f m",
            coordinate.latitude,
            coordinate.longitude,
            location.horizontalAccuracy
        )
        // Always pluralized — keeps the debug readout (and the maestro
        // `[0-9]+ points` assertion) stable regardless of count.
        countLabel.text = "\(pointCount) points"
        countLabel.isHidden = false
    }
}
