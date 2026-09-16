package fr.armandmgt.velo.features.record

import android.content.Context

/**
 * Whether pause automatique is switched on, stored per device in the same
 * preferences file as [Sport.lastUsed]. Defaults to **on** — the setting exists
 * to let a rider turn it off, not to make them find it first.
 *
 * Kept out of [AutoPauseDetector] so the detector itself stays free of `Context`.
 */
object AutoPauseSetting {
    private const val PREFS = "recording_prefs"
    private const val ENABLED_KEY = "recording.autoPauseEnabled"

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(ENABLED_KEY, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(ENABLED_KEY, enabled).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
