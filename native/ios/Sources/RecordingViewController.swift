import UIKit

/// The native recording surface (#41, S1 walking skeleton).
///
/// For now this is a placeholder: no location, no sensors, no persistence —
/// just the screen and its lifecycle, presented full-screen over the tabs by
/// `RecordTabBarController`. S2+ fill in the live stats, map, and a recording
/// session that lives *outside* this view controller (an on-device store), so
/// the screen can come and go without affecting an in-progress recording.
///
/// Two exits, distinct on purpose for later:
/// - **Fermer** (close): will simply leave the screen — recording keeps running
///   in the background and the tab-bar Record button reflects that.
/// - **Arrêter** (stop): will end and finalize the recording.
///
/// S1 has no recording state yet, so both currently just `dismiss`.
final class RecordingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Enregistrement"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Fermer",
            primaryAction: UIAction { [weak self] _ in self?.close() }
        )

        setupPlaceholder()
    }

    // MARK: - Layout

    private func setupPlaceholder() {
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

        let placeholder = UILabel()
        placeholder.text = "Bientôt : GPS, vitesse, distance…"
        placeholder.font = .preferredFont(forTextStyle: .subheadline)
        placeholder.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [glyph, elapsed, placeholder])
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

    // MARK: - Actions

    /// S1: leave the screen. S2+: keep recording in the background.
    private func close() {
        dismiss(animated: true)
    }

    /// S1: leave the screen. S2+: end and finalize the recording.
    private func stop() {
        dismiss(animated: true)
    }
}
