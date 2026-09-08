import UIKit

/// The split table — one row per Tour (S12a — #60).
///
/// Flat like the rest of the recording surfaces: hairline-separated rows,
/// uppercase muted column heads, monospaced digits. The lap in progress is called
/// out with an accent rule down its left edge and a tinted row, rather than a
/// punctuation mark that is easy to miss mid-ride.
///
/// Laps are device-local: this table is the only place they are ever shown
/// (see `docs/adr/0001-laps-stay-on-the-device.md`).
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
        addArrangedSubview(FlatStyle.hairline())
        for (index, split) in splits.enumerated() {
            addArrangedSubview(row(for: split))
            if index < splits.count - 1 {
                addArrangedSubview(FlatStyle.hairline())
            }
        }
    }

    // MARK: - Rows

    private func headerRow() -> UIView {
        let row = gridRow(
            lap: FlatStyle.caption("#"),
            distance: FlatStyle.caption("Dist."),
            time: FlatStyle.caption("Temps"),
            speed: FlatStyle.caption(usesPace ? "Allure" : "Moy.")
        )
        row.directionalLayoutMargins = .init(top: 0, leading: 20, bottom: 7, trailing: 20)
        return row
    }

    private func row(for split: LapSplit) -> UIView {
        let weight: UIFont.Weight = split.isInProgress ? .bold : .regular
        let lap = FlatStyle.number(size: 16, weight: .bold)
        lap.text = "\(split.ordinal)"

        let distance = FlatStyle.number(size: 18, weight: split.isInProgress ? .bold : .semibold)
        distance.text = "\(RecordingFormatters.distanceKilometers(split.distance)) km"

        let time = FlatStyle.number(size: 18, weight: weight)
        time.text = RecordingFormatters.elapsedString(split.elapsed)

        let speed = FlatStyle.number(size: 18, weight: weight, color: Palette.muted)
        speed.text = RecordingFormatters.speedOrPace(split.averageSpeed, usesPace: usesPace)

        let row = gridRow(lap: lap, distance: distance, time: time, speed: speed)
        row.directionalLayoutMargins = .init(top: 13, leading: 20, bottom: 13, trailing: 20)

        guard split.isInProgress else { return row }

        // Tinted, with an accent rule down the leading edge.
        let container = UIView()
        container.backgroundColor = Palette.accent.withAlphaComponent(0.08)
        container.translatesAutoresizingMaskIntoConstraints = false

        let rule = UIView()
        rule.backgroundColor = Palette.accent
        rule.translatesAutoresizingMaskIntoConstraints = false

        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        container.addSubview(rule)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.topAnchor.constraint(equalTo: container.topAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rule.widthAnchor.constraint(equalToConstant: 3),
        ])
        return container
    }

    /// Lap number in a fixed column, then three equal right-aligned columns.
    private func gridRow(lap: UILabel, distance: UILabel, time: UILabel, speed: UILabel) -> UIStackView {
        lap.textAlignment = .left
        [distance, time, speed].forEach { $0.textAlignment = .right }

        let stack = UIStackView(arrangedSubviews: [lap, distance, time, speed])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true

        NSLayoutConstraint.activate([
            lap.widthAnchor.constraint(equalToConstant: 26),
            time.widthAnchor.constraint(equalTo: distance.widthAnchor),
            speed.widthAnchor.constraint(equalTo: distance.widthAnchor),
        ])
        return stack
    }
}
