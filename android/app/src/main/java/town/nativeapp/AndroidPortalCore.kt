package town.nativeapp

import android.content.Context
import android.content.pm.PackageManager
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId

internal fun jsonArray(items: Iterable<Any>) = JSONArray().apply { items.forEach { put(it) } }
internal fun JSONObject.text(key: String, max: Int = 500, required: Boolean = true): String {
    val value = optString(key, "").trim()
    require((!required || value.isNotEmpty()) && value.length <= max) { "Invalid $key" }
    return value
}
internal fun JSONObject.time(key: String): Long = Instant.parse(text(key, 40)).toEpochMilli()
internal fun digest(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }

/** Local policy is authoritative. Neither tool arguments nor the Rust child can enable it. */
object AndroidPortalPolicy {
    val groups = linkedMapOf("calendar" to "日历", "contacts" to "通讯录", "reminders" to "提醒",
        "clock" to "系统闹钟与倒计时", "phone" to "拨号", "notifications" to "其他应用通知",
        "location" to "位置", "geofences" to "地点提醒", "health" to "健康数据", "shares" to "分享收件箱")
    @Volatile var foreground = false
    fun owner(context: Context): String = Vault(context).load()?.let { runCatching { digest(Connection.parse(it).endpoint) }.getOrNull() }.orEmpty()
    fun enabled(context: Context, owner: String, group: String, write: Boolean = false) = owner.isNotEmpty() &&
        context.getSharedPreferences("android_portal_policy", 0).getBoolean("$owner.$group.${if (write) "write" else "read"}", false)
    fun set(context: Context, owner: String, group: String, write: Boolean, enabled: Boolean) {
        require(owner.isNotEmpty() && group in groups)
        context.getSharedPreferences("android_portal_policy", 0).edit().putBoolean("$owner.$group.${if (write) "write" else "read"}", enabled).commit()
        if (write && group in listOf("reminders", "geofences")) AndroidPortalRestoreJob.enqueue(context)
    }
    fun requireAccess(context: Context, owner: String, group: String, write: Boolean = false) {
        check(owner.isNotEmpty() && owner == owner(context)) { "Being identity changed; restart Portal" }
        check(enabled(context, owner, group, write)) { "$group ${if (write) "write" else "read"} disabled; enable in Android Portal settings" }
    }
    fun permission(context: Context, permission: String) {
        check(context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) { "Android permission required: $permission" }
    }
    fun allowedApps(context: Context, owner: String): Set<String> = context.getSharedPreferences("android_portal_policy", 0)
        .getStringSet("$owner.notification_apps", emptySet()).orEmpty().toSet()
    fun setApps(context: Context, owner: String, apps: Set<String>) {
        context.getSharedPreferences("android_portal_policy", 0).edit().putStringSet("$owner.notification_apps", apps).apply()
    }
}

/** Atomic private storage, isolated by Being; no data is included in Android backups. */
class AndroidPortalStore(private val context: Context, val owner: String) {
    init { require(owner.matches(Regex("[0-9a-f]{64}"))) }
    private val file get() = AtomicFile(File(File(context.noBackupFilesDir, "android-portal").apply { mkdirs() }, "$owner.json"))
    private fun read(): JSONObject = if (!file.baseFile.exists()) JSONObject() else JSONObject(file.openRead().bufferedReader().use { it.readText() })
    private fun save(data: JSONObject) {
        val output = file.startWrite()
        try { output.write(data.toString().toByteArray()); file.finishWrite(output) }
        catch (e: Exception) { file.failWrite(output); throw e }
    }
    fun list(bucket: String): List<JSONObject> = synchronized(lock) {
        val array = read().optJSONArray(bucket) ?: JSONArray()
        (0 until array.length()).map { array.getJSONObject(it) }
    }
    fun get(bucket: String, id: String) = list(bucket).firstOrNull { it.optString("id") == id }
    fun put(bucket: String, row: JSONObject, max: Int = 500) = synchronized(lock) {
        val data = read(); val rows = list(bucket).filter { it.optString("id") != row.getString("id") }
        check(rows.size < max) { "$bucket limit reached; delete old entries" }
        data.put(bucket, jsonArray(rows + row)); save(data)
    }
    fun remove(bucket: String, id: String) = synchronized(lock) {
        val data = read(); data.put(bucket, jsonArray(list(bucket).filter { it.optString("id") != id })); save(data)
    }
    fun activity(tool: String, status: String) = synchronized(lock) {
        val data = read(); val rows = list("activity").takeLast(99)
        data.put("activity", jsonArray(rows + JSONObject().put("id", java.util.UUID.randomUUID().toString())
            .put("time", Instant.now().toString()).put("tool", tool).put("status", status))); save(data)
    }
    fun once(key: String, args: JSONObject, authorize: () -> Unit, operation: () -> JSONObject): JSONObject = synchronized(operationLocks.getOrPut(owner) { Any() }) {
        // Recheck after waiting: a previous operation may have held this lock while
        // the user revoked access or switched Being. This also guards cached replies.
        authorize()
        val fingerprint = digest(args.toString())
        get("requests", key)?.let { check(it.getString("fingerprint") == fingerprint) { "request_id reused with different arguments" }; return@synchronized it.getJSONObject("result") }
        val result = operation()
        if (list("requests").size >= 400) remove("requests", list("requests").first().getString("id"))
        put("requests", JSONObject().put("id", key).put("fingerprint", fingerprint).put("result", result))
        result
    }
    companion object { private val lock = Any(); private val operationLocks = java.util.concurrent.ConcurrentHashMap<String, Any>() }
}

object AndroidPortalRules {
    fun interval(args: JSONObject, maxDays: Long = 366): Pair<Long, Long> {
        val start = args.time("start"); val end = args.time("end")
        require(end > start && end - start <= maxDays * 86400000L) { "Invalid time range (maximum $maxDays days)" }
        return start to end
    }
    fun recurrence(value: String): String? {
        if (value.isBlank()) return null
        require(Regex("FREQ=(DAILY|WEEKLY|MONTHLY)(;INTERVAL=([1-9]|[1-9][0-9]))?(;COUNT=([1-9][0-9]{0,2}))?").matches(value)) { "Supported recurrence: FREQ=DAILY/WEEKLY/MONTHLY[;INTERVAL=N][;COUNT=N]" }
        return value
    }
    fun nextReminder(time: Long, repeat: String, zone: String, now: Long): Long? {
        if (repeat == "none") return null
        require(repeat in listOf("daily", "weekly"))
        var next = Instant.ofEpochMilli(time).atZone(ZoneId.of(zone))
        do { next = next.plusDays(if (repeat == "daily") 1 else 7) } while (next.toInstant().toEpochMilli() <= now)
        return next.toInstant().toEpochMilli()
    }
}
