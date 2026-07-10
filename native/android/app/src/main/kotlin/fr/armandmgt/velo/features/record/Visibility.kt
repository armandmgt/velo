package fr.armandmgt.velo.features.record

import androidx.annotation.StringRes
import fr.armandmgt.velo.R

/**
 * The visibility a recording is uploaded as (#41, S14 — #67). Mirrors the iOS
 * `Visibility` and the server's `Activity` visibility enum.
 *
 * [wire] is the authoritative `activity[visibility]` value. The review screen
 * lets the user choose before upload; it defaults to [PRIVATE], matching the
 * server's column default (privacy-safe).
 */
enum class Visibility(
    val wire: String,
    @StringRes val nameRes: Int,
) {
    PRIVATE("private", R.string.visibility_private),
    SHAREABLE("shareable", R.string.visibility_shareable),
    PUBLIC("public", R.string.visibility_public);

    companion object {
        val DEFAULT = PRIVATE
    }
}
