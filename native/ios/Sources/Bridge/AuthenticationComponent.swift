import HotwireNative
import UIKit

/// Mounted by `sessions/_meta` whenever the Rails layout is rendered for an
/// authenticated user. Receiving the "connect" message here is the native
/// shell's signal that the current page is past the auth wall, so the
/// `SceneDelegate` can swap the window root from the unauthenticated login
/// navigator to the tab-bar controller.
final class AuthenticationComponent: BridgeComponent {
    override class var name: String { "authentication" }

    override func onReceive(message: Message) {
        NotificationCenter.default.post(name: .didSignIn, object: nil)
    }
}

extension Notification.Name {
    static let didSignIn = Notification.Name("didSignIn")
}
