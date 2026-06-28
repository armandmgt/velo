package fr.armandmgt.velo.features.record

import android.content.Context
import androidx.annotation.StringRes
import fr.armandmgt.velo.R

/**
 * The sport a recording is uploaded as (#41, S9 — #57). Mirrors the iOS `Sport`.
 *
 * [wire] is the authoritative `activity[sport]` value (one of the 14 `Activity`
 * enum cases on the server). [gpxType] is the best-effort `<trk><type>` also
 * emitted into the GPX for self-containedness — the param wins server-side, and
 * `workout` has no GPX mapping (see the S0 contract,
 * `docs/native-recording/s0-gpx-upload-contract.md` §3).
 */
enum class Sport(
    val wire: String,
    val gpxType: String?,
    @StringRes val nameRes: Int,
) {
    BIKE("bike", "cycling", R.string.sport_bike),
    MOUNTAIN_BIKE_RIDE("mountain_bike_ride", "mountainbiking", R.string.sport_mountain_bike_ride),
    GRAVEL_RIDE("gravel_ride", "gravelbiking", R.string.sport_gravel_ride),
    VIRTUAL_RIDE("virtual_ride", "virtualride", R.string.sport_virtual_ride),
    E_BIKE_RIDE("e_bike_ride", "ebiking", R.string.sport_e_bike_ride),
    RUN("run", "running", R.string.sport_run),
    TRAIL_RUN("trail_run", "trailrunning", R.string.sport_trail_run),
    VIRTUAL_RUN("virtual_run", "virtualrunning", R.string.sport_virtual_run),
    WALK("walk", "walking", R.string.sport_walk),
    HIKE("hike", "hiking", R.string.sport_hike),
    ALPINE_SKI("alpine_ski", "alpineski", R.string.sport_alpine_ski),
    NORDIC_SKI("nordic_ski", "nordicski", R.string.sport_nordic_ski),
    SWIM("swim", "swimming", R.string.sport_swim),
    WORKOUT("workout", null, R.string.sport_workout);

    companion object {
        private const val PREFS = "recording_prefs"
        private const val LAST_USED_KEY = "recording.lastUsedSport"

        /**
         * The sport chosen for the previous recording, so the picker defaults to
         * it. Falls back to [BIKE] on first run or an unknown stored value.
         */
        fun lastUsed(context: Context): Sport {
            val raw = prefs(context).getString(LAST_USED_KEY, null) ?: return BIKE
            return entries.firstOrNull { it.wire == raw } ?: BIKE
        }

        fun setLastUsed(context: Context, sport: Sport) {
            prefs(context).edit().putString(LAST_USED_KEY, sport.wire).apply()
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }
}
