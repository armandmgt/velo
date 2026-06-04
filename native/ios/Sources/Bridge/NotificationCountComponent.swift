import HotwireNative
import UIKit

/// Mirrors the web "sorties à nommer" bell: shows a bell nav-bar button with a
/// numeric badge for the count, hidden when zero. Display-only (the web
/// controller expects no reply).
final class NotificationCountComponent: BridgeComponent {
    override class var name: String { "notification-count" }

    static let barButtonTag = 1002

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }

    override func onReceive(message: Message) {
        guard let event = Event(rawValue: message.event) else { return }
        switch event {
        case .connect: handleConnect(message: message)
        case .disconnect: removeButton()
        }
    }

    private func handleConnect(message: Message) {
        guard let data: MessageData = message.data(), let viewController else { return }

        guard data.count > 0 else {
            removeButton()
            return
        }

        let item = UIBarButtonItem(customView: BellBadgeView(count: data.count))
        viewController.navigationItem.setBridgeRightBarButton(item, tag: Self.barButtonTag)
    }

    private func removeButton() {
        viewController?.navigationItem.setBridgeRightBarButton(nil, tag: Self.barButtonTag)
    }
}

// MARK: Badge view

/// A bell glyph with a small count badge in the top-right corner.
private final class BellBadgeView: UIView {
    init(count: Int) {
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 30))

        let bell = UIImageView(image: UIImage(systemName: "bell"))
        bell.tintColor = .label
        bell.contentMode = .scaleAspectFit
        bell.frame = bounds
        addSubview(bell)

        let badge = UILabel()
        badge.text = count > 99 ? "99+" : "\(count)"
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = .systemRed
        badge.textAlignment = .center
        badge.sizeToFit()

        let diameter = max(16, badge.frame.width + 8)
        badge.frame = CGRect(x: bounds.width - diameter + 6, y: -4, width: diameter, height: 16)
        badge.layer.cornerRadius = 8
        badge.layer.masksToBounds = true
        addSubview(badge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: Events

private extension NotificationCountComponent {
    enum Event: String {
        case connect
        case disconnect
    }
}

// MARK: Message data

private extension NotificationCountComponent {
    struct MessageData: Decodable {
        let count: Int
    }
}
