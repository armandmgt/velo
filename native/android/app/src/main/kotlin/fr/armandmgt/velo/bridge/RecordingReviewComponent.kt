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
 * Hands the finished recording to the review screen, which is the web
 * `/activities/new`. Mirrors the iOS `RecordingReviewComponent`.
 */
class RecordingReviewComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    private val fragment get() = delegate.destination.fragment

    /**
     * The recording this page was opened for, taken when it first connects.
     * Committing or discarding clears this one, never whatever is pending by then,
     * so a resent review and a fresh one can't clear each other's.
     */
    private var handoff: RecordingHandoff.Payload? = null

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
     * `null` leaves the page reading as the plain upload form, which is also the
     * right answer if encoding fails.
     */
    private fun encodedHandoff(): String? {
        val handoff = handoff ?: RecordingHandoff.pending ?: return null
        this.handoff = handoff
        return runCatching { RecordingHandoff.encode(handoff) }
            .onFailure { Log.e("RecordingReviewComponent", "handoff encoding failed", it) }
            .getOrNull()
    }

    private fun handleCommitted(message: Message) {
        val url = message.data<CommittedData>()?.url
        clearRecording()

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
                clearRecording()
                fragment.activity?.onBackPressedDispatcher?.onBackPressed()
            }
            .setNegativeButton(R.string.recording_discard_cancel, null)
            .show()
    }

    private fun clearRecording() {
        val handoff = handoff ?: return
        this.handoff = null
        if (RecordingHandoff.pending?.sessionId == handoff.sessionId) RecordingHandoff.pending = null

        // The activity's scope, not the fragment's: the review is popped right
        // after this, which would cancel the delete with it.
        val activity = fragment.activity ?: return
        val dao = RecordingDatabase.get(activity.applicationContext).recordingDao()
        activity.lifecycleScope.launch { dao.deleteSession(handoff.sessionId) }
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
