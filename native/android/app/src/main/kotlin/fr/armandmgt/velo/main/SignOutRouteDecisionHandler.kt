package fr.armandmgt.velo.main

import android.content.Intent
import dev.hotwire.core.config.Hotwire
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router

/**
 * Mirror of the iOS shell's `is_after_sign_out_path` proposal-handling. When
 * any navigator inside [MainActivity] proposes a visit to a location flagged
 * with `is_after_sign_out_path` (set on /session/new + /users/new by the
 * server's path-configuration), we cancel the in-app navigation and swap
 * back to [LoginActivity].
 *
 * Must be registered ahead of [dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler]
 * so this handler gets a chance to match first.
 */
class SignOutRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "sign-out"

    override fun matches(location: String, configuration: NavigatorConfiguration): Boolean {
        return Hotwire.config.pathConfiguration.properties(location)["is_after_sign_out_path"] as? Boolean == true
    }

    override fun handle(
        location: String,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ): Router.Decision {
        // The unauthenticated LoginActivity also routes to /session/new at
        // cold start — accept that visit normally. Only intercept when the
        // proposal comes from the authenticated MainActivity.
        if (activity !is MainActivity) return Router.Decision.NAVIGATE

        val back = Intent(activity, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        activity.startActivity(back)
        activity.finish()
        return Router.Decision.CANCEL
    }
}
