package fr.armandmgt.velo.bridge

import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import androidx.appcompat.widget.PopupMenu
import androidx.appcompat.widget.Toolbar
import androidx.core.content.res.ResourcesCompat
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import fr.armandmgt.velo.R
import kotlinx.serialization.Serializable

/**
 * Renders the web navbar's hidden menu items as a native icon button in the
 * toolbar. Tapping the button opens a PopupMenu with per-item icons. Tapping
 * an item replies its index so the web controller clicks the matching link/form.
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
        toolbar.menu.add(GROUP_ID, ITEM_ID, 0, toolbar.context.getString(R.string.menu_open)).apply {
            setIcon(R.drawable.ic_person)
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            setOnMenuItemClickListener {
                showPopupMenu(data.items, toolbar)
                true
            }
        }
    }

    private fun showPopupMenu(items: List<Item>, anchor: Toolbar) {
        val context = anchor.context
        val popup = PopupMenu(context, anchor, Gravity.END)

        items.forEachIndexed { index, item ->
            popup.menu.add(Menu.NONE, index, index, item.title).also { menuItem ->
                item.androidImage?.let { name ->
                    val resId = context.resources.getIdentifier("ic_$name", "drawable", context.packageName)
                    if (resId != 0) {
                        menuItem.icon = ResourcesCompat.getDrawable(context.resources, resId, context.theme)
                    }
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            popup.setForceShowIcon(true)
        }

        popup.setOnMenuItemClickListener { menuItem ->
            replyTo("connect", SelectionData(menuItem.itemId))
            true
        }

        popup.show()
    }

    private fun removeItems() {
        toolbar?.menu?.removeGroup(GROUP_ID)
    }

    companion object {
        // Distinct from NotificationCountComponent so the two coexist in the menu.
        private const val GROUP_ID = 1001
        private const val ITEM_ID = 1003
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
