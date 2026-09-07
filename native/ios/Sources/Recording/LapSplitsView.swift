import UIKit

/// The list of splits — one row per Tour (S12a — #60).
///
/// Shared by the in-ride sheet (`LapSplitsViewController`, opened from the dock's
/// Tours cell) and the review screen, so a split reads identically before and
/// after Arrêter. Laps are device-local: this list is the only place they are
/// ever shown (ADR 0001).
final class LapSplitsView: UIStackView {
    /// Cycling sports read km/h, running sports min/km. Settable because the review
    /// screen lets the rider change sport after the fact, and the column has to
    /// follow.
    var usesPace: Bool

    init(usesPace: Bool) {
        self.usesPace = usesPace
        super.init(frame: .zero)
        axis = .vertical
        spacing = 0
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSplits(_ splits: [LapSplit]) {
        arrangedSubviews.forEach {
            removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        addArrangedSubview(headerRow())
        for split in splits {
            addArrangedSubview(separator())
            addArrangedSubview(row(for: split))
        }
    }

    // MARK: - Rows

    private func headerRow() -> UIView {
        let row = makeRow(
            lap: "TOUR",
            distance: "DIST.",
            time: "TEMPS",
            speed: usesPace ? "ALLURE" : "MOY.",
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: .secondaryLabel
        )
        return row
    }

    private func row(for split: LapSplit) -> UIView {
        // The lap in progress is called out so a short last split doesn't read as
        // a slow one.
        let lap = split.isInProgress ? "\(split.ordinal) ·" : "\(split.ordinal)"
        return makeRow(
            lap: lap,
            distance: "\(RecordingFormatters.distanceKilometers(split.distance)) km",
            time: RecordingFormatters.elapsedString(split.elapsed),
            speed: RecordingFormatters.speedOrPace(split.averageSpeed, usesPace: usesPace),
            font: .monospacedDigitSystemFont(ofSize: 15, weight: split.isInProgress ? .semibold : .regular),
            color: split.isInProgress ? .label : .label
        )
    }

    private func makeRow(
        lap: String,
        distance: String,
        time: String,
        speed: String,
        font: UIFont,
        color: UIColor
    ) -> UIView {
        let lapLabel = label(lap, font: font, color: color, alignment: .left)
        let distanceLabel = label(distance, font: font, color: color, alignment: .right)
        let timeLabel = label(time, font: font, color: color, alignment: .right)
        let speedLabel = label(speed, font: font, color: color, alignment: .right)

        let stack = UIStackView(arrangedSubviews: [lapLabel, distanceLabel, timeLabel, speedLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 10, leading: 4, bottom: 10, trailing: 4)

        NSLayoutConstraint.activate([
            lapLabel.widthAnchor.constraint(equalToConstant: 44),
            timeLabel.widthAnchor.constraint(equalTo: distanceLabel.widthAnchor),
            speedLabel.widthAnchor.constraint(equalTo: distanceLabel.widthAnchor),
        ])
        return stack
    }

    private func label(_ text: String, font: UIFont, color: UIColor, alignment: NSTextAlignment) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }

    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }
}
