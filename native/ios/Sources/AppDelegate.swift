import HotwireNative
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureHotwire()
        return true
    }

    private func configureHotwire() {
        // Prefix the WKWebView user agent. Hotwire Native already appends its own
        // "Hotwire Native iOS" marker, which is what turbo-rails' `hotwire_native_app?`
        // keys on to hide the web navbar and load native.css.
        Hotwire.config.applicationUserAgentPrefix = "Velo iOS;"

        // Native counterparts to the web's bridge Stimulus controllers.
        Hotwire.registerBridgeComponents([
            AuthenticationComponent.self,
            NavbarButtonsComponent.self,
            NotificationCountComponent.self,
        ])

        // Load the path configuration from the server, falling back to the copy
        // bundled in the app for the very first launch / offline starts.
        var sources: [PathConfiguration.Source] = [.server(AppConfig.pathConfigurationURL)]
        if let bundled = Bundle.main.url(forResource: "path-configuration", withExtension: "json") {
            sources.append(.file(bundled))
        }
        Hotwire.loadPathConfiguration(from: sources)
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
