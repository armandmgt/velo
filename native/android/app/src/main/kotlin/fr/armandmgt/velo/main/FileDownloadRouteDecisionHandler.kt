package fr.armandmgt.velo.main

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.widget.Toast
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router
import fr.armandmgt.velo.R

/**
 * Android counterpart to the iOS `FileDownloader`. Links to file exports (e.g.
 * GPX) are served as `application/gpx+xml` attachments the WebView can't
 * render: left to Hotwire's default routing they push a web destination that
 * fails to display and surfaces an error.
 *
 * We intercept those locations, hand them to the system [DownloadManager] —
 * forwarding the WebView's session cookies so the authenticated export route
 * doesn't bounce to the login page — and cancel the in-app navigation. The file
 * lands in the app's external files dir (no storage permission needed on any
 * supported API level) and DownloadManager posts a completion notification the
 * user can tap to open or share.
 *
 * Must be registered ahead of
 * [dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler] so it gets
 * a chance to match first.
 */
class FileDownloadRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "file-download"

    override fun matches(location: String, configuration: NavigatorConfiguration): Boolean {
        val path = Uri.parse(location).path ?: return false
        return path.endsWith(".gpx", ignoreCase = true)
    }

    override fun handle(
        location: String,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ): Router.Decision {
        val fileName = URLUtil.guessFileName(location, null, GPX_MIME_TYPE)

        val request = DownloadManager.Request(Uri.parse(location)).apply {
            CookieManager.getInstance().getCookie(location)?.let { addRequestHeader("Cookie", it) }
            setMimeType(GPX_MIME_TYPE)
            setTitle(fileName)
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS, fileName)
        }

        val downloadManager = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        downloadManager.enqueue(request)
        Toast.makeText(activity, R.string.download_started, Toast.LENGTH_SHORT).show()

        return Router.Decision.CANCEL
    }

    private companion object {
        const val GPX_MIME_TYPE = "application/gpx+xml"
    }
}
