import UIKit

/// The in-ride lap sheet, opened by tapping the dock's Tours cell (S12a — #60).
///
/// A sheet rather than a permanent dock section: riders glance at the dock mid
/// effort and read the table when they have a moment, so the splits shouldn't
/// cost the dock any standing height.
final class LapSplitsViewController: UIViewController {
    private let splits: [LapSplit]
    private let usesPace: Bool

    init(splits: [LapSplit], usesPace: Bool) {
        self.splits = splits
        self.usesPace = usesPace
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Tours"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityIdentifier = "lapSplitsTitle"

        let list = LapSplitsView(usesPace: usesPace)
        list.setSplits(splits)

        let close = UIButton(type: .system)
        close.setTitle("Fermer", for: .normal)
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [title, list, close])
        content.axis = .vertical
        content.spacing = 16
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

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])
    }
}
