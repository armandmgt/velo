import UIKit

/// The strap picker, opened from the armed card: the heart-rate straps nearby,
/// listed by name as they are found. Tapping one remembers it and connects.
final class HeartRatePairingViewController: UIViewController {
    private var monitor: HeartRateMonitor { .shared }

    private let list = UIStackView()
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init() {
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let title = UILabel()
        title.text = "Ceinture cardio"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = Palette.ink

        let intro = UILabel()
        intro.text = "Mettez votre ceinture : elle apparaît ici dès qu'elle détecte votre cœur."
        intro.font = .systemFont(ofSize: 14)
        intro.textColor = Palette.muted
        intro.numberOfLines = 0

        spinner.startAnimating()
        status.font = .systemFont(ofSize: 13, weight: .semibold)
        status.textColor = Palette.muted
        status.numberOfLines = 0
        let statusRow = UIStackView(arrangedSubviews: [spinner, status])
        statusRow.axis = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .center

        list.axis = .vertical
        list.spacing = 8

        let close = UIButton(type: .system)
        close.setTitle("Annuler", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        close.setTitleColor(Palette.ink, for: .normal)
        close.layer.borderWidth = 1
        close.layer.borderColor = Palette.border.cgColor
        close.heightAnchor.constraint(equalToConstant: 48).isActive = true
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)

        let content = UIStackView(arrangedSubviews: [title, intro, statusRow, list, close])
        content.axis = .vertical
        content.spacing = 12
        content.setCustomSpacing(20, after: list)
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 24, leading: 20, bottom: 12, trailing: 20)
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(render),
            name: .heartRateMonitorDidChange,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        monitor.startPairing()
        render()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        monitor.stopPairing()
    }

    @objc private func render() {
        let straps = monitor.discoveredStraps
        if monitor.isBluetoothUnavailable {
            spinner.stopAnimating()
            status.text = "Bluetooth est désactivé ou non autorisé pour Velo."
        } else {
            spinner.startAnimating()
            status.text = straps.isEmpty ? "Recherche des ceintures à proximité…" : "Touchez votre ceinture pour l'associer."
        }

        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for strap in straps {
            list.addArrangedSubview(row(for: strap))
        }
    }

    private func row(for strap: HeartRateMonitor.Strap) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = strap.name
        config.image = UIImage(systemName: "heart.fill")
        config.imagePadding = 10
        config.baseForegroundColor = Palette.ink
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in Palette.red }
        config.contentInsets = .init(top: 14, leading: 14, bottom: 14, trailing: 14)
        config.background.backgroundColor = .white
        config.background.cornerRadius = 0
        config.background.strokeColor = Palette.border
        config.background.strokeWidth = 1
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = .systemFont(ofSize: 16, weight: .semibold)
            return attrs
        }
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addAction(
            UIAction { [weak self] _ in
                self?.monitor.pair(with: strap)
                self?.dismiss(animated: true)
            },
            for: .primaryActionTriggered
        )
        return button
    }
}
