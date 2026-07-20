package fr.armandmgt.velo.main

import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.tabs.HotwireBottomTab
import fr.armandmgt.velo.BuildConfig
import fr.armandmgt.velo.R

private val dashboard = HotwireBottomTab(
    title = "Tableau de bord",
    iconResId = R.drawable.ic_dashboard,
    configuration = NavigatorConfiguration(
        name = "dashboard",
        navigatorHostId = R.id.dashboard_navigator_host,
        startLocation = BuildConfig.BASE_URL
    )
)

private val activities = HotwireBottomTab(
    title = "Activités",
    iconResId = R.drawable.ic_bike,
    configuration = NavigatorConfiguration(
        name = "activities",
        navigatorHostId = R.id.activities_navigator_host,
        startLocation = "${BuildConfig.BASE_URL}/activities"
    )
)

private val plannedRoutes = HotwireBottomTab(
    title = "Parcours",
    iconResId = R.drawable.ic_route,
    configuration = NavigatorConfiguration(
        name = "planned_routes",
        navigatorHostId = R.id.planned_routes_navigator_host,
        startLocation = "${BuildConfig.BASE_URL}/planned_routes"
    )
)

val mainTabs = listOf(dashboard, activities, plannedRoutes)

/**
 * Cross-tab routing lookups. The server's path-configuration tags each section
 * with the `tab` that owns it (see `ConfigurationsController::TAB_RULES`); those
 * identifiers match each tab's [NavigatorConfiguration.name] above, so a tab can
 * be resolved from a `tab` property by name.
 */
fun tabIndex(name: String): Int? =
    mainTabs.indexOfFirst { it.configuration.name == name }.takeIf { it >= 0 }

fun tabNavigatorHostId(name: String): Int? =
    mainTabs.firstOrNull { it.configuration.name == name }?.configuration?.navigatorHostId
