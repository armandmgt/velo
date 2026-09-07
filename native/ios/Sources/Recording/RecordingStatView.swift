import UIKit

/// A value-over-caption stat cell used in the recording metric/summary cards. The
/// caption is upper-cased for a tidy dashboard feel; the value is large (the
/// payload). Shared by the live dashboard and the post-stop review screen.
final class StatView: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    var value: String {
        get { valueLabel.text ?? "" }
        set { valueLabel.text = newValue }
    }

    var caption: String {
        get { captionLabel.text ?? "" }
        set { captionLabel.text = newValue.uppercased() }
    }

    init(caption: String) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        valueLabel.text = "—"
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6

        captionLabel.font = .preferredFont(forTextStyle: .caption2)
        captionLabel.textColor = .secondaryLabel
        captionLabel.textAlignment = .center
        // "Durée de déplacement" has to fit a third of the summary card.
        captionLabel.numberOfLines = 2
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.8
        captionLabel.text = caption.uppercased()

        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
