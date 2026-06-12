package fr.armandmgt.velo.main

import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import fr.armandmgt.velo.BuildConfig
import fr.armandmgt.velo.R

/**
 * Unauthenticated root. Mirrors the iOS shell's `unauthenticatedNavigator`:
 * a single Hotwire fragment that starts at `/session/new`. When the
 * `bridge--authentication` controller (mounted by the Rails layout's
 * `sessions/_meta` partial for authenticated users) fires its "connect"
 * message, the [fr.armandmgt.velo.bridge.AuthenticationComponent] swaps in
 * [MainActivity] and finishes this one.
 */
class LoginActivity : HotwireActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)
        findViewById<View>(R.id.login_nav_host).applyDefaultImeWindowInsets()
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "unauthenticated",
            startLocation = "${BuildConfig.BASE_URL}/session/new",
            navigatorHostId = R.id.login_nav_host
        )
    )
}
