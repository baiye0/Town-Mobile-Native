package town.nativeapp

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File

data class AppRelease(val version: String, val url: String, val notes: String, val assetUrl: String?)

object AppUpdates {
    private const val repository = "baiye0/Town-Mobile-Native"
    private val client = OkHttpClient()

    suspend fun latest(): AppRelease = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("https://api.github.com/repos/$repository/releases/latest")
            .header("Accept", "application/vnd.github+json").header("User-Agent", "Being-Android").build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "无法读取 GitHub Release（${response.code}）" }
            val json = JSONObject(response.body?.string().orEmpty())
            check(!json.optBoolean("draft") && !json.optBoolean("prerelease")) { "暂无正式版本" }
            val version = json.optString("tag_name").removePrefix("v")
            check(version.matches(Regex("\\d+\\.\\d+\\.\\d+"))) { "Release 版本号无效" }
            val assets = json.optJSONArray("assets")
            var apk: String? = null
            for (i in 0 until (assets?.length() ?: 0)) {
                val asset = assets!!.optJSONObject(i)
                if (asset?.optString("name")?.endsWith(".apk", true) == true) { apk = asset.optString("browser_download_url"); break }
            }
            AppRelease(version, json.optString("html_url"), json.optString("body"), apk)
        }
    }

    fun isNewer(latest: String, current: String): Boolean = compare(latest, current) > 0
    private fun compare(a: String, b: String): Int {
        val left = a.removePrefix("v").split('.').map { it.toIntOrNull() ?: 0 }
        val right = b.removePrefix("v").split('.').map { it.toIntOrNull() ?: 0 }
        return (0..2).firstOrNull { (left.getOrElse(it) { 0 }) != (right.getOrElse(it) { 0 }) }
            ?.let { left.getOrElse(it) { 0 }.compareTo(right.getOrElse(it) { 0 }) } ?: 0
    }

    suspend fun downloadAndInstall(context: Context, release: AppRelease) = withContext(Dispatchers.IO) {
        val url = release.assetUrl ?: error("该 Release 没有 Android APK")
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val file = File(dir, "being-${release.version}.apk")
        val request = Request.Builder().url(url).header("User-Agent", "Being-Android").build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "下载升级包失败（${response.code}）" }
            response.body!!.byteStream().use { input -> file.outputStream().use { output -> input.copyTo(output) } }
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
