import HotwireNative
import UIKit

/// Two-root scene. The window starts on the unauthenticated `navigator` whose
/// start location is `/session/new`. When the layout's `sessions/meta`
/// partial loads it fires the `bridge--authentication` connect message →
/// `AuthenticationComponent` posts `.didSignIn` → we swap the root to the
/// tab-bar controller. On the way back (logout), the path-config marks the
/// `/session/new` rule with `is_after_sign_out_path: true`; intercepting that
/// proposal swaps the root back.
class SceneDelegate: UIResponder, UIWindowSceneDelegate, NavigatorDelegate {
    var window: UIWindow?

    private lazy var unauthenticatedNavigator = Navigator(
        configuration: .init(
            name: "unauthenticated",
            startLocation: AppConfig.baseURL.appendingPathComponent("session/new")
        ),
        delegate: self
    )

    private lazy var tabBarController = RecordTabBarController(navigatorDelegate: self)

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = unauthenticatedNavigator.rootViewController
        window?.makeKeyAndVisible()
        unauthenticatedNavigator.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didSignIn),
            name: .didSignIn,
            object: nil
        )
    }

    // MARK: NavigatorDelegate

    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        // File exports (e.g. GPX) are served as attachments WKWebView can't
        // render. Download them natively — reusing the webview's session
        // cookies — and offer a share sheet instead of pushing a doomed visit.
        if proposal.url.pathExtension == "gpx" {
            FileDownloader.download(from: proposal.url, presentingFrom: navigator)
            return .reject
        }

        // The sign-out path-property only signals an *authenticated* webview
        // bouncing back to the login screen. The unauthenticated navigator's
        // own initial route to /session/new also carries this property —
        // accepting it there is required, otherwise nothing renders.
        let isSignOut = proposal.properties["is_after_sign_out_path"] as? Bool == true
        let fromTabBar = navigator !== unauthenticatedNavigator
        if isSignOut && fromTabBar {
            didSignOut()
            return .reject
        }
        return .accept
    }

    // MARK: Auth transitions

    @objc private func didSignIn() {
        guard window?.rootViewController !== tabBarController else { return }
        window?.rootViewController = tabBarController
        tabBarController.load(HotwireTab.all)
        tabBarController.selectedIndex = 0
    }

    private func didSignOut() {
        guard window?.rootViewController !== unauthenticatedNavigator.rootViewController else { return }
        window?.rootViewController = unauthenticatedNavigator.rootViewController
        unauthenticatedNavigator.rootViewController.popToRootViewController(animated: false)
        unauthenticatedNavigator.reload()
    }
}
