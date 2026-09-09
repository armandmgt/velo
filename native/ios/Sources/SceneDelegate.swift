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

        // Cross-tab routing. Each bottom tab owns a section of the app, but by
        // default a tapped link pushes onto whatever tab's stack it came from —
        // so an activity opened from the dashboard feed would land in the
        // dashboard stack, duplicating what the Activités tab owns. The server's
        // path-configuration tags each section with the tab that owns it; when a
        // proposal names a *different* tab than the one showing, switch to it and
        // route there, then reject so the originating navigator doesn't also
        // push it. Modals present over the current tab, so they're left alone.
        if fromTabBar,
           proposal.properties["context"] as? String != "modal",
           let tabName = proposal.properties["tab"] as? String,
           let targetIndex = HotwireTab.index(named: tabName),
           targetIndex != tabBarController.selectedIndex {
            tabBarController.selectedIndex = targetIndex
            tabBarController.activeNavigator.route(proposal.url)
            return .reject
        }

        return .accept
    }

    /// The review modal is terminal by design, which would trap a rider whose
    /// page can't load — and a ride ends where signal is worst. On a failed visit,
    /// hand back the Fermer we otherwise withhold.
    func visitableDidFailRequest(_ visitable: Visitable, error: HotwireNativeError, retryHandler: RetryBlock?) {
        let viewController = visitable.visitableViewController
        if let modal = viewController.navigationController,
           modal.isModalInPresentation,
           visitable.initialVisitableURL.path == "/activities/new" {
            modal.isModalInPresentation = false
            viewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Fermer",
                primaryAction: UIAction { [weak modal] _ in
                    modal?.presentingViewController?.dismiss(animated: true)
                }
            )
        }

        if let errorPresenter = visitable as? ErrorPresenter {
            errorPresenter.presentError(error, retryHandler: retryHandler)
        }
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
