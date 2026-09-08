package fr.armandmgt.velo.bridge

import android.app.AlertDialog
import android.util.Log
import androidx.lifecycle.lifecycleScope
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import fr.armandmgt.velo.R
import fr.armandmgt.velo.features.record.RecordingHandoff
import fr.armandmgt.velo.features.record.data.RecordingDatabase
import fr.armandmgt.velo.main.MainActivity
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

/**
 * The shell's half of the recording review (#116, ADR 0003 — supersedes #67).
 * Mirrors the iOS `RecordingReviewComponent`: the review screen is the web
 * `/activities/new`, and this hands it the finished recording.
 */
class RecordingReviewComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val fragment get() = delegate.destination.fragment

    override fun onReceive(message: Message) {
        when (message.event) {
            "connect" -> handleConnect()
            "committed" -> handleCommitted(message)
            "discard" -> handleDiscard()
            else -> Log.w("RecordingReviewComponent", "Unknown event: ${message.event}")
        }
    }

    private fun handleConnect() {
        replyTo("connect", HandoffData(handoff = encodedHandoff()))
    }

    /**
     * `null` when there is nothing to hand over. The page treats both the same
     * way, so a failure to encode degrades to the plain upload form.
     */
    private fun encodedHandoff(): String? {
        val pending = RecordingHandoff.pending ?: return null
        return runCatching { RecordingHandoff.encode(pending) }
            .onFailure { Log.e("RecordingReviewComponent", "handoff encoding failed", it) }
            .getOrNull()
    }

    /** Only now is it safe to drop the on-device recording (S0 §5). */
    private fun handleCommitted(message: Message) {
        val url = message.data<CommittedData>()?.url
        clearPendingRecording()

        val activity = fragment.activity as? MainActivity
        activity?.onBackPressedDispatcher?.onBackPressed()
        if (url != null) activity?.routeInTab("activities", url)
    }

    private fun handleDiscard() {
        val context = fragment.context ?: return
        AlertDialog.Builder(context)
            .setTitle(R.string.recording_discard_confirm_title)
            .setMessage(R.string.recording_discard_confirm_message)
            .setPositiveButton(R.string.recording_discard) { _, _ ->
                clearPendingRecording()
                fragment.activity?.onBackPressedDispatcher?.onBackPressed()
            }
            .setNegativeButton(R.string.recording_discard_cancel, null)
            .show()
    }

    private fun clearPendingRecording() {
        val pending = RecordingHandoff.pending ?: return
        RecordingHandoff.pending = null

        val context = fragment.context?.applicationContext ?: return
        val dao = RecordingDatabase.get(context).recordingDao()
        fragment.lifecycleScope.launch { dao.deleteSession(pending.sessionId) }
    }

    @Serializable
    data class CommittedData(
        val url: String? = null,
    )

    @Serializable
    data class HandoffData(
        val handoff: String? = null,
    )
}
