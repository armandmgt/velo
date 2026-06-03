package fr.armandmgt.velo.bridge

import android.util.Log
import android.view.LayoutInflater
import android.view.Menu
import android.view.MenuItem
import android.widget.TextView
import androidx.appcompat.widget.Toolbar
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import fr.armandmgt.velo.R
import kotlinx.serialization.Serializable

/**
 * Mirrors the web "sorties à nommer" bell: a toolbar bell with a numeric badge
 * for the count, hidden when zero. Display-only (the web controller expects no
 * reply).
 */
class NotificationCountComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val toolbar: Toolbar?
        get() = delegate.destination.toolbarForNavigation()

    override fun onReceive(message: Message) {
        when (message.event) {
            "connect" -> handleConnect(message)
            "disconnect" -> removeItem()
            else -> Log.w("NotificationCountComponent", "Unknown event: ${message.event}")
        }
    }

    private fun handleConnect(message: Message) {
        val data = message.data<MessageData>() ?: return
        val toolbar = toolbar ?: return

        removeItem()
        if (data.count <= 0) return

        val actionView = LayoutInflater.from(toolbar.context)
            .inflate(R.layout.notification_bell, toolbar, false)
        actionView.findViewById<TextView>(R.id.notification_badge).text =
            if (data.count > 99) "99+" else data.count.toString()

        toolbar.menu.add(Menu.NONE, ITEM_ID, 0, "Notifications").apply {
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            this.actionView = actionView
        }
    }

    private fun removeItem() {
        toolbar?.menu?.removeItem(ITEM_ID)
    }

    companion object {
        private const val ITEM_ID = 1002
    }

    @Serializable
    data class MessageData(val count: Int)
}
