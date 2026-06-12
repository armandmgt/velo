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

val mainTabs = listOf(dashboard, activities)
