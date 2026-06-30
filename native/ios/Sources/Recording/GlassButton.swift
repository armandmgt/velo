import UIKit

/// A Liquid Glass button, matching the tab-bar Record button's treatment
/// (`RecordTabBarController.makeRecordButton`): `prominentGlass` (tinted, reads
/// against content) for primary colour actions, plain `glass` for secondary
/// ones, with a filled/tinted fallback below iOS 26. Shared by the recording
/// dashboard and the review screen.
enum GlassButton {
    static func make(prominent: Bool, tint: UIColor? = nil) -> UIButton {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = prominent ? .prominentGlass() : .glass()
        } else {
            config = prominent ? .filled() : .tinted()
        }
        if let tint {
            config.baseBackgroundColor = tint
            config.baseForegroundColor = .white
        }
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
