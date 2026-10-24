import UIKit

/// Recordings that were stopped but never reached the server — the review page
/// failed to load, or the app died before the upload committed.
///
/// Pushed from the recording screen's armed card rather than shown as a sheet:
/// a sheet over the full-screen recording modal is out of Maestro's reach.
/// Envoyer reopens the web review on the stored recording, exactly as Arrêter
/// does; Supprimer deletes it after a confirmation.
final class UnsentRecordingsViewController: UIViewController {
    private var controller: RecordingController { .shared }

    /// Hands the chosen recording back to the recording screen, which owns the
    /// modal and so is the one that can dismiss it onto the review.
    private let onSend: (RecordingSession) -> Void

    private let list = UIStackView()

    init(onSend: @escaping (RecordingSession) -> Void) {
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Non envoyés"
        view.backgroundColor = Palette.page

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.page
        appearance.shadowColor = .clear
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance

        let intro = UILabel()
        intro.text = "Ces enregistrements sont restés sur le téléphone. Envoyez-les pour créer l'activité."
        intro.font = .systemFont(ofSize: 14)
        intro.textColor = Palette.muted
        intro.numberOfLines = 0

        list.axis = .vertical
        list.spacing = 12

        let content = UIStackView(arrangedSubviews: [intro, list])
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(content)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: .unsentRecordingsDidChange,
            object: nil
        )
        reload()
    }

    @objc private func reload() {
        let recordings = controller.unsentRecordings
        // Nothing left to send: the armed card is the only useful place to be.
        guard !recordings.isEmpty else {
            if navigationController?.topViewController === self {
                navigationController?.popViewController(animated: true)
            }
            return
        }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for session in recordings {
            list.addArrangedSubview(card(for: session))
        }
    }

    // MARK: - Rows

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func card(for session: RecordingSession) -> UIView {
        let stats = session.finalStats
        let sport = session.recordedSport

        let icon = UIImageView(image: UIImage(systemName: sport.symbolName))
        icon.tintColor = Palette.ink
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let sportLabel = UILabel()
        sportLabel.text = sport.displayName
        sportLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        sportLabel.textColor = Palette.ink

        let date = UILabel()
        date.text = Self.dateFormatter.string(from: session.startedAt)
        date.font = .systemFont(ofSize: 13)
        date.textColor = Palette.muted
        date.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [icon, sportLabel, date])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let distance = FlatStyle.number(size: 24, weight: .heavy, color: Palette.accent)
        distance.text = "\(RecordingFormatters.distanceKilometers(stats.distance)) km"
        let elapsed = FlatStyle.number(size: 24, weight: .heavy)
        elapsed.text = RecordingFormatters.elapsedString(stats.elapsed)

        let numbers = UIStackView(arrangedSubviews: [
            column(caption: "Distance", value: distance),
            FlatStyle.hairline(vertical: true),
            column(caption: "Temps écoulé", value: elapsed),
        ])
        numbers.axis = .horizontal
        numbers.spacing = 16
        numbers.alignment = .fill

        let delete = button(title: "Supprimer", titleColor: Palette.red, background: .white, border: Palette.redBorder)
        delete.addAction(UIAction { [weak self] _ in self?.confirmDelete(session) }, for: .primaryActionTriggered)
        let send = button(title: "Envoyer", titleColor: Palette.greenText, background: Palette.green, border: nil)
        send.addAction(UIAction { [weak self] _ in self?.onSend(session) }, for: .primaryActionTriggered)

        let actions = UIStackView(arrangedSubviews: [delete, send])
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [header, numbers, actions])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = FlatStyle.card(border: Palette.borderDock)
        card.accessibilityIdentifier = "unsentRecording"
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            icon.widthAnchor.constraint(equalToConstant: 20),
            delete.heightAnchor.constraint(equalToConstant: 44),
        ])
        return card
    }

    private func column(caption: String, value: UILabel) -> UIView {
        let stack = UIStackView(arrangedSubviews: [FlatStyle.caption(caption), value])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    private func button(title: String, titleColor: UIColor, background: UIColor, border: UIColor?) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = background
        if let border {
            button.layer.borderWidth = 1
            button.layer.borderColor = border.cgColor
        }
        return button
    }

    // MARK: - Actions

    private func confirmDelete(_ session: RecordingSession) {
        let alert = UIAlertController(
            title: "Supprimer cet enregistrement ?",
            message: "Cette action est définitive. L'enregistrement ne sera pas envoyé.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Supprimer", style: .destructive) { [weak self] _ in
            self?.controller.discard(session)
        })
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        present(alert, animated: true)
    }
}
