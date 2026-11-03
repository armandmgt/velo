// PROTOTYPE (app-owned tabs spike, #11). Throwaway: a Compose NavigationBar owns
// the tabs; each tab still hosts a Hotwire NavigatorHost. Replaces
// HotwireBottomNavigationController.
package fr.armandmgt.velo.spike

import android.os.Bundle
import android.view.View
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import androidx.navigation.NavController
import androidx.navigation.NavDestination
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorHost
import dev.hotwire.navigation.tabs.HotwireBottomTab
import fr.armandmgt.velo.ui.theme.VeloTheme

class AppBottomBar(
    private val activity: HotwireActivity,
    private val view: ComposeView,
    private val tabs: List<HotwireBottomTab>,
) : NavController.OnDestinationChangedListener {
    var selectedIndex by mutableIntStateOf(0)
        private set
    private var destinationIsModal by mutableStateOf(false)
    private var keyboardVisible by mutableStateOf(false)
    private var listener: ((Int) -> Unit)? = null

    fun load(initialIndex: Int = 0) {
        view.setContent {
            VeloTheme {
                AnimatedVisibility(
                    visible = !destinationIsModal && !keyboardVisible,
                    enter = slideInVertically { it },
                    exit = slideOutVertically { it },
                ) {
                    NavigationBar {
                        tabs.forEachIndexed { index, tab ->
                            NavigationBarItem(
                                selected = index == selectedIndex,
                                onClick = { selectTab(index) },
                                icon = { Icon(painterResource(tab.iconResId), contentDescription = null) },
                                label = { Text(tab.title) },
                                modifier = Modifier.testTag("tab_${tab.configuration.name}"),
                            )
                        }
                    }
                }
            }
        }
        ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets ->
            keyboardVisible = insets.isVisible(WindowInsetsCompat.Type.ime())
            insets
        }
        tabs.forEach { it.navigatorHost.navController.addOnDestinationChangedListener(this) }
        switchTab(initialIndex)
    }

    fun setOnTabSelectedListener(listener: (Int) -> Unit) {
        this.listener = listener
    }

    /** Reselecting the current tab clears its stack, as Hotwire's controller did. */
    fun selectTab(index: Int) {
        if (index == selectedIndex) {
            tabs[index].navigatorHost.navigator.clearAll()
            return
        }
        switchTab(index)
        listener?.invoke(index)
    }

    fun route(location: String) {
        activity.delegate.currentNavigator?.route(location)
    }

    override fun onDestinationChanged(controller: NavController, destination: NavDestination, arguments: Bundle?) {
        if (activity.delegate.currentNavigator?.host?.navController == controller) {
            destinationIsModal = arguments?.getString("presentation-context").equals("modal", ignoreCase = true)
        }
    }

    private fun switchTab(index: Int) {
        selectedIndex = index
        activity.delegate.setCurrentNavigator(tabs[index].configuration)
        tabs.forEachIndexed { i, tab ->
            activity.findViewById<View>(tab.configuration.navigatorHostId)?.isVisible = i == index
        }
        // A modal left open on the tab we came from mustn't keep the bar hidden here.
        destinationIsModal = false
    }

    private val HotwireBottomTab.navigatorHost: NavigatorHost
        get() = activity.supportFragmentManager.findFragmentById(configuration.navigatorHostId) as NavigatorHost
}
