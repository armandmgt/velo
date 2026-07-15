package fr.armandmgt.velo.main

import dev.hotwire.core.config.Hotwire
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router

/**
 * Cross-tab routing — the Android counterpart to the iOS shell's cross-tab
 * handling in `SceneDelegate.handle`.
 *
 * Each bottom tab owns a section of the app, but Hotwire Native routes a tapped
 * link onto whichever tab's navigator proposed it — so an activity opened from
 * the dashboard feed would land in the dashboard stack, duplicating what the
 * Activités tab already owns. The server's path-configuration tags each section
 * with the tab that owns it (a `tab` property, see
 * `ConfigurationsController::TAB_RULES`); when a proposal's owning tab differs
 * from the tab it came from, we switch to that tab and route there instead,
 * cancelling the in-app navigation so the originating navigator doesn't also
 * push it.
 *
 * The proposing navigator is identified by [NavigatorConfiguration.name], which
 * matches the `tab` identifiers; comparing the two both scopes this to genuine
 * cross-tab jumps and breaks the recursion when [MainActivity.routeInTab] routes
 * on the destination tab (there the names match, so we fall through to NAVIGATE).
 *
 * Must be registered ahead of
 * [dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler] so it gets
 * a chance to match first.
 */
class TabRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "tab-routing"

    override fun matches(location: String, configuration: NavigatorConfiguration): Boolean {
        val properties = Hotwire.config.pathConfiguration.properties(location)
        // Modals present over the current tab, so leave them on it.
        if (properties["context"] as? String == "modal") return false
        val targetTab = properties["tab"] as? String ?: return false
        return targetTab != configuration.name && tabNavigatorHostId(targetTab) != null
    }

    override fun handle(
        location: String,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ): Router.Decision {
        if (activity !is MainActivity) return Router.Decision.NAVIGATE
        val targetTab = Hotwire.config.pathConfiguration.properties(location)["tab"] as? String
            ?: return Router.Decision.NAVIGATE

        activity.routeInTab(targetTab, location)
        return Router.Decision.CANCEL
    }
}
