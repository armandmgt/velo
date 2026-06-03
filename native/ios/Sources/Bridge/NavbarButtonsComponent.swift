import HotwireNative
import UIKit

/// Renders the web navbar's menu items (hidden in native by native.css) as a
/// native overflow (ellipsis) menu in the nav bar. Tapping an item replies the
/// item's index so the web controller clicks the matching link/form.
final class NavbarButtonsComponent: BridgeComponent {
    override class var name: String { "navbar-buttons" }

    static let barButtonTag = 1001

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

        let actions = data.items.enumerated().map { index, item in
            UIAction(
                title: item.title,
                image: item.iosImage.flatMap { UIImage(systemName: $0) }
            ) { [weak self] _ in
                self?.reply(to: Event.connect.rawValue, with: SelectionData(index: index))
            }
        }

        let button = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: actions)
        )
        viewController.navigationItem.setBridgeRightBarButton(button, tag: Self.barButtonTag)
    }

    private func removeButton() {
        viewController?.navigationItem.setBridgeRightBarButton(nil, tag: Self.barButtonTag)
    }
}

// MARK: Events

private extension NavbarButtonsComponent {
    enum Event: String {
        case connect
        case disconnect
    }
}

// MARK: Message data

private extension NavbarButtonsComponent {
    struct MessageData: Decodable {
        let items: [Item]
    }

    struct Item: Decodable {
        let title: String
        let iosImage: String?
        let androidImage: String?
    }

    struct SelectionData: Encodable {
        let index: Int
    }
}
