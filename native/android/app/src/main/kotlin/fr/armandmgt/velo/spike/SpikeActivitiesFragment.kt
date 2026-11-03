// PROTOTYPE (native mixed-tabs spike, #8). Throwaway: a rough Compose activity
// list that replaces the Hotwire `/activities` page and pushes Hotwire pages.
package fr.armandmgt.velo.spike

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.widget.LinearLayout
import androidx.appcompat.widget.Toolbar
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.google.android.material.appbar.MaterialToolbar
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireFragment
import fr.armandmgt.velo.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class SpikeActivity(val name: String, val location: String, val distance: Double, val url: String)

@HotwireDestinationDeepLink(uri = "hotwire://fragment/activities_native")
class SpikeActivitiesFragment : HotwireFragment() {
    private val activities = mutableStateOf<List<SpikeActivity>>(emptyList())
    private val error = mutableStateOf<String?>(null)
    private val fetchCount = mutableIntStateOf(0)
    private lateinit var toolbar: MaterialToolbar

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val context = requireContext()
        toolbar = MaterialToolbar(context).apply { title = "Activités" }
        val compose = ComposeView(context).apply {
            setContent { MaterialTheme { SpikeActivitiesList() } }
        }
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(toolbar, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            addView(compose, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }
    }

    override fun toolbarForNavigation(): Toolbar = toolbar

    // Refetch on every reveal: the native stand-in for Turbo Stream refreshes.
    override fun onStart() {
        super.onStart()
        lifecycleScope.launch { load() }
    }

    private suspend fun load() {
        val url = "${BuildConfig.BASE_URL}/activities.json"
        try {
            val body = withContext(Dispatchers.IO) {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.setRequestProperty("Accept", "application/json")
                CookieManager.getInstance().getCookie(url)?.let { connection.setRequestProperty("Cookie", it) }
                connection.instanceFollowRedirects = false
                val status = connection.responseCode
                if (status != 200) error("HTTP $status")
                connection.inputStream.bufferedReader().readText()
            }
            val array = JSONObject(body).getJSONArray("activities")
            activities.value = (0 until array.length()).map { i ->
                val item = array.getJSONObject(i)
                SpikeActivity(item.getString("name"), item.getString("location"), item.optDouble("distance", 0.0), item.getString("url"))
            }
            fetchCount.intValue += 1
            error.value = null
        } catch (e: Exception) {
            error.value = e.message
        }
    }

    @androidx.compose.runtime.Composable
    private fun SpikeActivitiesList() {
        LazyColumn(Modifier.semantics { testTagsAsResourceId = true }) {
            item {
                Text(
                    "Native list · fetch #${fetchCount.intValue}",
                    Modifier.padding(16.dp).testTag("spikeNativeMarker"),
                    style = MaterialTheme.typography.labelSmall,
                )
                error.value?.let { Text(it, Modifier.padding(16.dp).testTag("spikeError"), color = Color.Red) }
            }
            items(activities.value) { activity ->
                Column(
                    Modifier.fillMaxWidth().clickable { navigator.route(activity.url) }
                        .padding(16.dp).testTag("spikeActivityRow")
                ) {
                    Text(activity.name, style = MaterialTheme.typography.titleMedium)
                    Text("${activity.location} · ${"%.1f km".format(activity.distance)}", style = MaterialTheme.typography.bodyMedium)
                }
                HorizontalDivider()
            }
        }
    }
}
