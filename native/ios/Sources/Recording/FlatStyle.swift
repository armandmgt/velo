import UIKit

/// The flat design vocabulary shared by the native recording screens.
///
/// The recording screen was redesigned flat per `Recording.dc.html` — white
/// sharp-cornered cards with a thin border over the map, uppercase muted
/// captions, monospaced-digit numbers — and the review screen follows it (the
/// map-hero direction). Keeping the tokens in one place is what stops the two
/// screens drifting into different-looking halves of one flow.

enum Palette {
    static func hex(_ v: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
    static let ink = hex(0x161616)        // primary text        — oklch(20% 0 0)
    static let muted = hex(0x555555)      // captions / secondary — oklch(45% 0 0)
    static let border = hex(0xCECECE)     // chip / button border — oklch(85% 0 0)
    static let borderDock = hex(0xD7D7D7) // dock border          — oklch(88% 0 0)
    static let divider = hex(0xE4E4E4)    // internal dividers    — oklch(92% 0 0)
    static let grabber = hex(0xC4C4C4)    // grab handle          — oklch(82% 0 0)
    static let green = hex(0x20C45F)      // Démarrer fill        — oklch(72% 0.19 150)
    static let greenText = hex(0x08351A)  // Démarrer text        — oklch(24% 0.06 153)
    static let redBorder = hex(0xFF627E)  // Arrêter border       — oklch(71% 0.194 13.4)
    static let red = hex(0xDD1B53)        // Arrêter / rec pill   — oklch(58% 0.22 13.4)
    static let paused = hex(0xD36000)     // paused pill          — oklch(62% 0.18 56)
    static let page = hex(0xF4F4F4)       // screen behind cards  — oklch(96% 0 0)
    /// The app accent (the web theme's `--color-primary`), delivered by the server
    /// in the path configuration — the same orange the live trace is drawn in.
    static var accent: UIColor { MapConfig.current.accentColor }
}

/// Builders for the flat surfaces those tokens describe.
enum FlatStyle {
    /// A flat white card: 1px border, sharp corners, a soft shadow. Never rounded
    /// — square corners are the whole signature of this design.
    static func card(
        border: UIColor = Palette.border,
        shadowOpacity: Float = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.borderWidth = 1
        view.layer.borderColor = border.cgColor
        if shadowOpacity > 0 {
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = shadowOpacity
            view.layer.shadowRadius = shadowRadius
            view.layer.shadowOffset = CGSize(width: 0, height: shadowY)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func hairline(vertical: Bool = false) -> UIView {
        let view = UIView()
        view.backgroundColor = Palette.divider
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: vertical ? .horizontal : .vertical)
        view.setContentCompressionResistancePriority(.required, for: vertical ? .horizontal : .vertical)
        if vertical {
            view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        } else {
            view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }
        return view
    }

    /// An uppercase muted caption — the label style under every number.
    static func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Palette.muted
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }

    /// A number in the dashboard's monospaced-digit face.
    static func number(size: CGFloat, weight: UIFont.Weight, color: UIColor = Palette.ink) -> UILabel {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        return label
    }
}

/// A flat three-way picker: bordered cells split by hairlines, the selected one
/// filled. `UISegmentedControl` draws its own rounded pill that can't be squared
/// off without poking at private subviews, and rounded corners are exactly what
/// this design doesn't have — so the control is drawn rather than restyled.
final class FlatSegmentedControl: UIView {
    private let titles: [String]
    private var cells: [UIButton] = []

    /// Index of the selected cell.
    private(set) var selectedIndex: Int
    var onChange: ((Int) -> Void)?

    init(titles: [String], selectedIndex: Int = 0) {
        self.titles = titles
        self.selectedIndex = selectedIndex
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        layer.borderWidth = 1
        layer.borderColor = Palette.border.cgColor

        var arranged: [UIView] = []
        for (index, title) in titles.enumerated() {
            if index > 0 { arranged.append(FlatStyle.hairline(vertical: true)) }
            let cell = UIButton(type: .system)
            cell.setTitle(title, for: .normal)
            cell.titleLabel?.adjustsFontSizeToFitWidth = true
            cell.titleLabel?.minimumScaleFactor = 0.8
            cell.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            cells.append(cell)
            arranged.append(cell)
        }

        let row = UIStackView(arrangedSubviews: arranged)
        row.axis = .horizontal
        row.alignment = .fill
        // Proportional, not equal: "Lien partageable" is three times the width of
        // "Privée", and equal cells would either truncate it or strand whitespace.
        row.distribution = .fillProportionally
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 32),
        ])
        applySelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func select(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        applySelection()
        onChange?(index)
    }

    private func applySelection() {
        for (index, cell) in cells.enumerated() {
            let isSelected = index == selectedIndex
            cell.backgroundColor = isSelected ? Palette.hex(0xEDEDED) : .white
            cell.setTitleColor(isSelected ? Palette.ink : Palette.muted, for: .normal)
            cell.titleLabel?.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
            cell.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
    }
}
