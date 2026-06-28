package fr.armandmgt.velo.features.record

import android.util.Log
import android.webkit.CookieManager
import fr.armandmgt.velo.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException

/**
 * Uploads a serialized recording to the Rails server (#41, S9 — #57). Mirrors the
 * iOS `ActivityUploader`.
 *
 * Posts the GPX to the existing `POST /activities` as multipart form data,
 * reusing the WebView's session cookie ([CookieManager]) for auth — the same
 * trick [fr.armandmgt.velo.main.FileDownloadRouteDecisionHandler] uses for
 * authenticated downloads. The endpoint answers `Accept: application/json` with
 * `201 { id, url }` on success and `422 { errors: [...] }` on a validation
 * failure (the S0 contract, §4–5). The field is named `activity[fit_file]` even
 * for GPX — the server dispatches on the `.gpx` filename.
 */
object ActivityUploader {
    sealed interface UploadResult {
        data class Success(val url: String) : UploadResult

        /** Server rejected the activity (e.g. missing sport); carries the server's messages. */
        data class Validation(val messages: List<String>) : UploadResult

        /** Transport/encoding failure or an unexpected status. */
        data class Network(val detail: String? = null) : UploadResult
    }

    private const val TAG = "ActivityUploader"
    private const val GPX_MEDIA_TYPE = "application/gpx+xml"

    private val client by lazy { OkHttpClient() }
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun upload(gpx: String, sport: Sport): UploadResult = withContext(Dispatchers.IO) {
        val endpoint = "${BuildConfig.BASE_URL}/activities"

        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("activity[sport]", sport.wire)
            .addFormDataPart(
                "activity[fit_file]",
                "recording.gpx",
                gpx.toRequestBody(GPX_MEDIA_TYPE.toMediaType()),
            )
            .build()

        val request = Request.Builder()
            .url(endpoint)
            .header("Accept", "application/json")
            .apply {
                CookieManager.getInstance().getCookie(BuildConfig.BASE_URL)?.let { header("Cookie", it) }
            }
            .post(body)
            .build()

        try {
            client.newCall(request).execute().use { response ->
                val payload = response.body?.string().orEmpty()
                when (response.code) {
                    201 -> parseCreated(payload)
                    422 -> UploadResult.Validation(parseErrors(payload))
                    else -> UploadResult.Network("HTTP ${response.code}")
                }
            }
        } catch (e: IOException) {
            Log.w(TAG, "upload failed", e)
            UploadResult.Network(e.message)
        }
    }

    private fun parseCreated(payload: String): UploadResult =
        runCatching { json.decodeFromString<CreatedActivity>(payload) }
            .map { UploadResult.Success(it.url) }
            .getOrElse { UploadResult.Network("unreadable 201 body") }

    private fun parseErrors(payload: String): List<String> =
        runCatching { json.decodeFromString<ValidationErrors>(payload).errors }
            .getOrDefault(emptyList())

    @Serializable
    private data class CreatedActivity(val id: Long, val url: String)

    @Serializable
    private data class ValidationErrors(val errors: List<String>)
}
