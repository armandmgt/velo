package fr.armandmgt.velo

import android.app.Application
import dev.hotwire.core.bridge.BridgeComponentFactory
import dev.hotwire.core.bridge.KotlinXJsonConverter
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerBridgeComponents
import dev.hotwire.navigation.config.registerFragmentDestinations
import dev.hotwire.navigation.config.registerRouteDecisionHandlers
import dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler
import dev.hotwire.navigation.routing.BrowserTabRouteDecisionHandler
import dev.hotwire.navigation.routing.SystemNavigationRouteDecisionHandler
import fr.armandmgt.velo.bridge.AuthenticationComponent
import fr.armandmgt.velo.bridge.NavbarButtonsComponent
import fr.armandmgt.velo.bridge.NotificationCountComponent
import fr.armandmgt.velo.features.web.WebFragment
import fr.armandmgt.velo.main.SignOutRouteDecisionHandler

class VeloApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        configureHotwire()
    }

    private fun configureHotwire() {
        // Load the path configuration from the server, falling back to the copy
        // bundled in assets for the first launch / offline starts.
        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                assetFilePath = "json/path-configuration.json",
                remoteFileUrl = "${BuildConfig.BASE_URL}/configurations/android_v1"
            )
        )

        // Every URL routes to the web fragment unless a rule says otherwise.
        Hotwire.defaultFragmentDestination = WebFragment::class
        Hotwire.registerFragmentDestinations(WebFragment::class)

        // Native counterparts to the web's bridge Stimulus controllers.
        Hotwire.registerBridgeComponents(
            BridgeComponentFactory("authentication", ::AuthenticationComponent),
            BridgeComponentFactory("navbar-buttons", ::NavbarButtonsComponent),
            BridgeComponentFactory("notification-count", ::NotificationCountComponent),
        )

        // Replaces the library defaults; SignOutRouteDecisionHandler runs
        // first so /session/new visits from the authenticated MainActivity
        // are intercepted before AppNavigation hands them to in-app routing.
        Hotwire.registerRouteDecisionHandlers(
            SignOutRouteDecisionHandler(),
            AppNavigationRouteDecisionHandler(),
            BrowserTabRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler(),
        )

        // The "Hotwire Native" marker the prefix produces is what turbo-rails'
        // `hotwire_native_app?` keys on to hide the web navbar and load native.css.
        Hotwire.config.applicationUserAgentPrefix = "Velo Android;"
        Hotwire.config.debugLoggingEnabled = BuildConfig.DEBUG
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG
        Hotwire.config.jsonConverter = KotlinXJsonConverter()
    }
}
