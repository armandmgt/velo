package fr.armandmgt.velo.main

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.tabs.HotwireBottomNavigationController
import dev.hotwire.navigation.tabs.navigatorConfigurations
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.RecordingActivity

class MainActivity : HotwireActivity() {
    private lateinit var bottomNavigationController: HotwireBottomNavigationController

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.root).applyDefaultImeWindowInsets()

        initializeBottomTabs()

        findViewById<FloatingActionButton>(R.id.record_fab).setOnClickListener {
            startActivity(Intent(this, RecordingActivity::class.java))
        }
    }

    override fun navigatorConfigurations() = mainTabs.navigatorConfigurations

    private fun initializeBottomTabs() {
        val bottomNavigationView = findViewById<BottomNavigationView>(R.id.bottom_nav)
        bottomNavigationController = HotwireBottomNavigationController(this, bottomNavigationView)
        bottomNavigationController.load(mainTabs, selectedTabIndex = 0)
    }

    fun showDashboard() {
        bottomNavigationController.selectTab(DASHBOARD_TAB_INDEX)
        delegate.findNavigatorHost(R.id.dashboard_navigator_host)
            ?.navigator?.session?.webView?.scrollTo(0, 0)
    }

    private companion object {
        const val DASHBOARD_TAB_INDEX = 0
    }
}
