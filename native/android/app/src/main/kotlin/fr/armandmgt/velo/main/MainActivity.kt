package fr.armandmgt.velo.main

import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import fr.armandmgt.velo.BuildConfig
import fr.armandmgt.velo.R

class MainActivity : HotwireActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.main_nav_host).applyDefaultImeWindowInsets()
    }

    // A single navigation stack for the MVP. A bottom-tab layout
    // (HotwireBottomNavigationController) is a planned enhancement.
    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = BuildConfig.BASE_URL,
            navigatorHostId = R.id.main_nav_host
        )
    )
}
