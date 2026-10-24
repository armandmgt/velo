package fr.armandmgt.velo.main

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.isVisible
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.NavController
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.tabs.HotwireBottomNavigationController
import dev.hotwire.navigation.tabs.navigatorConfigurations
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import fr.armandmgt.velo.BuildConfig
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.RecordingActivity
import fr.armandmgt.velo.features.record.RecordingHandoff
import fr.armandmgt.velo.features.record.data.RecordingDatabase
import kotlinx.coroutines.launch

class MainActivity : HotwireActivity() {
    private lateinit var bottomNavigationController: HotwireBottomNavigationController
    private lateinit var recordFab: FloatingActionButton
    private lateinit var unsentBadge: TextView

    /** Recordings that never reached the server, counted on the Record FAB. */
    private var unsentCount = 0
    private var selectedTabIndex = DASHBOARD_TAB_INDEX

    // A finished recording parks its handoff and asks for the review, which is
    // the web `/activities/new`, presented modally by the path config.
    private val recordLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode != RESULT_OK) return@registerForActivityResult
            if (!(result.data?.getBooleanExtra(RecordingActivity.EXTRA_OPEN_REVIEW, false) ?: false)) {
                return@registerForActivityResult
            }
            bottomNavigationController.route("${BuildConfig.BASE_URL}/activities/new")
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.root).applyDefaultImeWindowInsets()

        // Resolve the FAB before the tabs load: their navigator hosts can become
        // ready (→ onNavigatorReady) as part of that, and the modal listener there
        // touches recordFab.
        recordFab = findViewById(R.id.record_fab)
        unsentBadge = findViewById(R.id.record_fab_badge)

        initializeBottomTabs()

        // The FAB is contextual to the selected tab: Record on the dashboard,
        // a "+" that opens the web "new" form on the Activités / Parcours tabs.
        updateFab(DASHBOARD_TAB_INDEX)
        bottomNavigationController.setOnTabSelectedListener { index, _ -> updateFab(index) }

        val dao = RecordingDatabase.get(this).recordingDao()
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                dao.stoppedSessions().collect { sessions ->
                    unsentCount = sessions.size
                    updateUnsentBadge()
                }
            }
        }
    }

    override fun navigatorConfigurations() = mainTabs.navigatorConfigurations

    override fun onNavigatorReady(navigator: Navigator) {
        super.onNavigatorReady(navigator)
        // The FAB floats in the Activity's root layout, so a modal destination
        // (e.g. a "/new" form) would otherwise overlap it. The bottom nav hides
        // itself on modal destinations (HotwireBottomNavigationController); the FAB
        // isn't managed there, so mirror that behaviour by watching each tab
        // navigator's destination changes and hiding the FAB while a modal shows.
        navigator.host.navController.addOnDestinationChangedListener(fabModalVisibilityListener)
    }

    private val fabModalVisibilityListener =
        NavController.OnDestinationChangedListener { controller, _, arguments ->
            // Only react to the active tab's navigator, matching
            // HotwireBottomNavigationController's own modal-visibility guard.
            if (delegate.currentNavigator?.host?.navController != controller) {
                return@OnDestinationChangedListener
            }
            // The typed accessor is library-internal; read the raw argument
            // ("modal" / "default") the path config sets for MODAL_PATTERNS.
            val presentationContext = arguments?.getString("presentation-context")
            recordFab.isVisible = !presentationContext.equals("modal", ignoreCase = true)
            updateUnsentBadge()
        }

    private fun initializeBottomTabs() {
        val bottomNavigationView = findViewById<BottomNavigationView>(R.id.bottom_nav)
        bottomNavigationController = HotwireBottomNavigationController(this, bottomNavigationView)
        bottomNavigationController.load(mainTabs, selectedTabIndex = 0)
    }

    /** Point the FAB's icon, label and tap action at whatever the selected tab needs. */
    private fun updateFab(selectedTabIndex: Int) {
        this.selectedTabIndex = selectedTabIndex
        updateUnsentBadge()
        when (selectedTabIndex) {
            tabIndex("activities") -> configureFab(R.drawable.ic_add, R.string.new_activity) {
                // The plain upload form, never the review of a recording parked by
                // an earlier Arrêter whose page failed to load.
                RecordingHandoff.pending = null
                bottomNavigationController.route("${BuildConfig.BASE_URL}/activities/new")
            }
            tabIndex("planned_routes") -> configureFab(R.drawable.ic_add, R.string.new_route) {
                bottomNavigationController.route("${BuildConfig.BASE_URL}/planned_routes/new")
            }
            else -> configureFab(R.drawable.ic_record, R.string.record) {
                recordLauncher.launch(Intent(this, RecordingActivity::class.java))
            }
        }
    }

    /** Only on the Record FAB: the "+" modes have nothing to do with recordings. */
    private fun updateUnsentBadge() {
        val isRecordFab = selectedTabIndex != tabIndex("activities") && selectedTabIndex != tabIndex("planned_routes")
        unsentBadge.isVisible = recordFab.isVisible && isRecordFab && unsentCount > 0
        unsentBadge.text = unsentCount.toString()
        unsentBadge.contentDescription =
            resources.getQuantityString(R.plurals.recording_unsent_count, unsentCount, unsentCount)
    }

    private fun configureFab(iconResId: Int, contentDescriptionResId: Int, onClick: () -> Unit) {
        recordFab.setImageResource(iconResId)
        recordFab.contentDescription = getString(contentDescriptionResId)
        recordFab.setOnClickListener { onClick() }
    }

    fun showDashboard() {
        bottomNavigationController.selectTab(DASHBOARD_TAB_INDEX)
        delegate.findNavigatorHost(R.id.dashboard_navigator_host)
            ?.navigator?.session?.webView?.scrollTo(0, 0)
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
