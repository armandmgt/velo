package fr.armandmgt.velo.main

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
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

    // A finished recording uploads out-of-band and returns the new activity's URL;
    // open it in the Activités tab's webview (#57).
    private val recordLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode != RESULT_OK) return@registerForActivityResult
            val url = result.data?.getStringExtra(RecordingActivity.EXTRA_ACTIVITY_URL)
                ?: return@registerForActivityResult
            openActivity(url)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.root).applyDefaultImeWindowInsets()

        initializeBottomTabs()

        findViewById<FloatingActionButton>(R.id.record_fab).setOnClickListener {
            recordLauncher.launch(Intent(this, RecordingActivity::class.java))
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

    /** Switch to the Activités tab and route its navigator to the freshly created activity (#57). */
    private fun openActivity(url: String) {
        routeInTab("activities", url)
    }

    /**
     * Switch to the [tabName] tab and route its navigator to [url]. Backs
     * cross-tab routing ([TabRouteDecisionHandler]): a link whose section is
     * owned by another tab lands in that tab's stack instead of the current one.
     */
    fun routeInTab(tabName: String, url: String) {
        val index = tabIndex(tabName) ?: return
        val hostId = tabNavigatorHostId(tabName) ?: return
        bottomNavigationController.selectTab(index)
        val host = delegate.findNavigatorHost(hostId) ?: return
        // Post so the tab's navigator is ready when it was never opened before.
        host.view?.post { host.navigator?.route(url) }
    }

    private companion object {
        const val DASHBOARD_TAB_INDEX = 0
    }
}
