package fr.armandmgt.velo.features.web

import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment

// The default destination every web URL is presented in. The `uri` matches the
// `hotwire://fragment/web` referenced by the server's android_v1 path config.
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class WebFragment : HotwireWebFragment()
