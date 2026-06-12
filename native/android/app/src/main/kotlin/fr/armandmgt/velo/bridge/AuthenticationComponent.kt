package fr.armandmgt.velo.bridge

import android.content.Intent
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import fr.armandmgt.velo.main.LoginActivity
import fr.armandmgt.velo.main.MainActivity

/**
 * Mounted by the Rails `sessions/_meta` partial whenever the layout renders
 * for an authenticated user. Receiving the "connect" message here is the
 * native shell's signal that the current page is past the auth wall — if we
 * are still in [LoginActivity], hand the user off to [MainActivity] and
 * finish the login activity so it does not stay on the back stack.
 */
class AuthenticationComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        if (message.event != "connect") return
        val activity = delegate.destination.fragment.activity as? LoginActivity ?: return
        val next = Intent(activity, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        activity.startActivity(next)
        activity.finish()
    }
}
