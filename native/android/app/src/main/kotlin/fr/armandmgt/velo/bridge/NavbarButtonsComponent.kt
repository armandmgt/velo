package fr.armandmgt.velo.bridge

import android.util.Log
import android.view.Menu
import android.view.MenuItem
import androidx.appcompat.widget.Toolbar
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.serialization.Serializable

/**
 * Renders the web navbar's menu items (hidden in native by native.css) as a
 * native 3-dot overflow menu in the toolbar. Tapping an item replies the item's
 * index so the web controller clicks the matching link/form.
 */
class NavbarButtonsComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val toolbar: Toolbar?
        get() = delegate.destination.toolbarForNavigation()

    override fun onReceive(message: Message) {
        when (message.event) {
            "connect" -> handleConnect(message)
            "disconnect" -> removeItems()
            else -> Log.w("NavbarButtonsComponent", "Unknown event: ${message.event}")
        }
    }

    private fun handleConnect(message: Message) {
        val data = message.data<MessageData>() ?: return
        val toolbar = toolbar ?: return

        removeItems()
        data.items.forEachIndexed { index, item ->
            toolbar.menu.add(GROUP_ID, Menu.NONE, index, item.title).apply {
                setShowAsAction(MenuItem.SHOW_AS_ACTION_NEVER)
                setOnMenuItemClickListener {
                    replyTo("connect", SelectionData(index))
                    true
                }
            }
        }
    }

    private fun removeItems() {
        toolbar?.menu?.removeGroup(GROUP_ID)
    }

    companion object {
        // Distinct from NotificationCountComponent so the two coexist in the menu.
        private const val GROUP_ID = 1001
    }

    @Serializable
    data class MessageData(val items: List<Item>)

    @Serializable
    data class Item(
        val title: String,
        val iosImage: String? = null,
        val androidImage: String? = null
    )

    @Serializable
    data class SelectionData(val index: Int)
}
