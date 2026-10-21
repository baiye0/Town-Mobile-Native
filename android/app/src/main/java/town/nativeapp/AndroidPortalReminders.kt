package town.nativeapp

import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

object AndroidPortalNotices {
    fun show(context: Context, key: String, title: String, body: String, actionId: String? = null) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("portal-events", "Portal 提醒与待处理操作", NotificationManager.IMPORTANCE_HIGH))
        val intent = Intent(context, AndroidPortalActionActivity::class.java).setData(Uri.parse("portal-action:$key")).putExtra("action_id", actionId)
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        manager.notify(key.hashCode(), Notification.Builder(context, "portal-events").setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title).setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(pending).setAutoCancel(true).build())
    }
}

class AndroidPortalReminders(private val context: Context, private val owner: String) {
    private val store = AndroidPortalStore(context, owner)
    fun call(action: String, args: JSONObject): JSONObject = when (action) {
        "list" -> JSONObject().put("reminders", jsonArray(store.list("reminders")))
        "create", "update" -> {
            check(context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()) { "Enable app notifications before scheduling reminders" }
            val id = if (action == "create") UUID.randomUUID().toString() else args.text("id", 80).also { check(store.get("reminders", it) != null) { "Reminder not found" } }
            val time = args.time("at"); require(time > System.currentTimeMillis()) { "Reminder must be in the future" }
            val zone = args.optString("timezone", ZoneId.systemDefault().id); ZoneId.of(zone)
            val repeat = args.optString("repeat", "none"); require(repeat in listOf("none", "daily", "weekly"))
            val row = JSONObject().put("id", id).put("title", args.text("title", 200)).put("at", Instant.ofEpochMilli(time).toString())
                .put("timezone", zone).put("repeat", repeat).put("status", "scheduled")
            val exact = args.optBoolean("exact", false)
            check(!exact || exactAvailable(context)) { "Exact alarm access required; enable in system settings or use exact=false" }
            row.put("exact", exact); val previous = store.get("reminders", id)
            store.put("reminders", row)
            try { schedule(row) } catch (e: Exception) { if (previous == null) store.remove("reminders", id) else { store.put("reminders", previous); runCatching { schedule(previous) } }; throw e }
            row.put("timing", if (exact) "exact_requested" else "approximate_system_may_delay")
        }
        "delete" -> {
            val id = args.text("id", 80); check(store.get("reminders", id) != null) { "Reminder not found" }
            context.getSystemService(AlarmManager::class.java).cancel(pending(id)); store.remove("reminders", id)
            context.getSystemService(NotificationManager::class.java).cancel((owner + id).hashCode())
            JSONObject().put("id", id).put("status", "deleted")
        }
        else -> error("Unknown reminders action")
    }
    private fun pending(id: String): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, AndroidPortalReminderReceiver::class.java).setAction("town.nativeapp.PORTAL_REMINDER")
            .setData(Uri.parse("portal-reminder:$owner/$id")).putExtra("owner", owner).putExtra("id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(row: JSONObject) {
        val manager = context.getSystemService(AlarmManager::class.java); val at = row.time("at")
        if (row.optBoolean("exact") && exactAvailable(context)) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(row.getString("id")))
        else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(row.getString("id")))
    }
    fun fire(id: String) {
        val row = store.get("reminders", id) ?: return
        if (row.optString("status") != "scheduled") return
        // An old broadcast after an update must not fire the replacement early.
        if (row.time("at") > System.currentTimeMillis() + 1000) { schedule(row); return }
        if (owner != AndroidPortalPolicy.owner(context) || !AndroidPortalPolicy.enabled(context, owner, "reminders", true)) {
            store.put("reminders", row.put("status", "paused")); return
        }
        AndroidPortalNotices.show(context, owner + id, row.getString("title"), "Being 日程提醒")
        store.activity("reminder", "delivered")
        val next = AndroidPortalRules.nextReminder(row.time("at"), row.getString("repeat"), row.getString("timezone"), System.currentTimeMillis())
        row.put("status", if (next == null) "delivered" else "scheduled")
        if (next != null) row.put("at", Instant.ofEpochMilli(next).toString())
        store.put("reminders", row); if (next != null) schedule(row)
    }
    fun restore() { store.list("reminders").filter { it.optString("status") == "scheduled" }.forEach { runCatching { schedule(it) } } }
    fun suspendAll() { store.list("reminders").filter { it.optString("status") == "scheduled" }.forEach { context.getSystemService(AlarmManager::class.java).cancel(pending(it.getString("id"))) } }
    companion object { fun exactAvailable(context: Context) = Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms() }
}

class AndroidPortalReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "town.nativeapp.PORTAL_REMINDER") { AndroidPortalRestoreJob.enqueue(context); return }
        val work = goAsync()
        java.util.concurrent.Executors.newSingleThreadExecutor().also { executor -> executor.execute {
            try {
                val owner = intent.getStringExtra("owner") ?: AndroidPortalPolicy.owner(context)
                if (owner.isNotEmpty()) {
                    val reminders = AndroidPortalReminders(context, owner)
                    reminders.fire(intent.getStringExtra("id") ?: return@execute)
                }
            } finally { work.finish(); executor.shutdown() }
        } }
    }
}
