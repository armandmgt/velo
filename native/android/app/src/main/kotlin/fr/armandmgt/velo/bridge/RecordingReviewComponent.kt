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
 * Mirrors the iOS `RecordingReviewComponent`.
 *
 * The review screen is the web `/activities/new`; this hands it the finished
 * recording and listens for what the rider does with it:
 * - **connect** → reply with the compressed handoff, or `null` when there is no
 *   pending recording (the tab bar's FAB routes to the same URL, where the page
 *   must read as the plain upload form).
 * - **committed** → the page's upload succeeded; clear the local session.
 * - **discard** → confirm, then drop the recording. Nothing was uploaded.
 *
 * The shell no longer uploads anything itself: `ActivityUploader` and
 * `RecordingGpxEncoder` are gone, and the GPX is encoded on the web from the
 * points this component sends.
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
     * The compressed handoff, or `null` when there is nothing to hand over — the
     * page treats both the same way, so a failure to encode degrades to the
     * upload form rather than to a broken review screen.
     */
    private fun encodedHandoff(): String? {
        val pending = RecordingHandoff.pending ?: return null
        return runCatching { RecordingHandoff.encode(pending) }
            .onFailure { Log.e("RecordingReviewComponent", "handoff encoding failed", it) }
            .getOrNull()
    }

    /**
     * The upload landed. Only now is it safe to drop the on-device recording —
     * the store is the source of truth until the server has confirmed (S0 §5,
     * weakened by ADR 0003 and bought back by the `recording_uuid` the page
     * submitted, which makes a replay resolve to this same activity).
     */
    private fun handleCommitted(message: Message) {
        val url = message.data<CommittedData>()?.url
        clearPendingRecording()

        val activity = fragment.activity as? MainActivity
        // Leave the review modal, then land on the created activity in the tab
        // that owns activities — mirroring the iOS component.
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
        /** Where the form submission landed — the created activity. */
        val url: String? = null,
    )

    @Serializable
    data class HandoffData(
        /** Raw DEFLATE, base64'd. `null` when there is no pending recording. */
        val handoff: String? = null,
    )
}
