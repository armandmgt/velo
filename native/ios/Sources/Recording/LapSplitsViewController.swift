import UIKit

/// The lap sheet — opened from the recording dock's Tours cell while riding, and
/// from the review screen's lap row afterwards (S12a — #60).
///
/// A sheet rather than a permanent section: riders glance at the dock mid-effort
/// and read the table when they have a moment, so the splits cost the dock no
/// standing height.
final class LapSplitsViewController: UIViewController {
    private let splits: [LapSplit]
    private let usesPace: Bool
    /// Totals for the header line, so the table has something to be a breakdown of.
    private let summary: String?

    init(splits: [LapSplit], usesPace: Bool, summary: String? = nil) {
        self.splits = splits
        self.usesPace = usesPace
        self.summary = summary
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
        title.text = "Tours"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = Palette.ink
        title.accessibilityIdentifier = "lapSplitsTitle"

        let totals = FlatStyle.number(size: 13, weight: .regular, color: Palette.muted)
        totals.text = summary
        totals.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [title, UIView(), totals])
        header.axis = .horizontal
        header.alignment = .lastBaseline
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = .init(top: 12, leading: 20, bottom: 14, trailing: 20)

        let list = LapSplitsView(usesPace: usesPace)
        list.setSplits(splits)

        let footnote = UILabel()
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = Palette.muted
        footnote.numberOfLines = 0
        if let running = splits.first(where: \.isInProgress) {
            footnote.text = "Le tour \(running.ordinal) est en cours."
        }
        let footnoteRow = UIStackView(arrangedSubviews: [footnote])
        footnoteRow.isLayoutMarginsRelativeArrangement = true
        footnoteRow.directionalLayoutMargins = .init(top: 8, leading: 20, bottom: 0, trailing: 20)
        footnoteRow.isHidden = footnote.text == nil

        let close = UIButton(type: .system)
        close.setTitle("Fermer", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        close.setTitleColor(Palette.ink, for: .normal)
        close.backgroundColor = .white
        close.layer.borderWidth = 1
        close.layer.borderColor = Palette.border.cgColor
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let closeRow = UIStackView(arrangedSubviews: [close])
        closeRow.isLayoutMarginsRelativeArrangement = true
        closeRow.directionalLayoutMargins = .init(top: 20, leading: 20, bottom: 12, trailing: 20)

        let content = UIStackView(arrangedSubviews: [header, list, footnoteRow, closeRow])
        content.axis = .vertical
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            close.heightAnchor.constraint(equalToConstant: 46),
        ])
    }
}
