package town.nativeapp

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.AlarmClock
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

class AndroidPortalActions(private val context: Context, private val owner: String) {
    private val store = AndroidPortalStore(context, owner)
    fun queue(kind: String, args: JSONObject): JSONObject {
        intent(kind, args) // Validate before storing a pending action.
        val id = UUID.randomUUID().toString()
        val row = JSONObject().put("id", id).put("kind", kind).put("arguments", args).put("status", "pending_user_action").put("created", Instant.now().toString())
        // Keep the queue bounded without letting completed history permanently
        // prevent new handoffs. Pending operations are never silently discarded.
        val actions = store.list("actions")
        if (actions.size >= 100) actions.firstOrNull { it.optString("status") in listOf("cancelled", "handed_to_system_unconfirmed") }
            ?.let { store.remove("actions", it.getString("id")) }
        store.put("actions", row, 100)
        AndroidPortalNotices.show(context, id, "Being 操作待处理", "请打开本机 Portal 确认${if (kind == "phone") "拨号" else "闹钟或倒计时"}", id)
        return JSONObject().put("id", id).put("status", "pending_user_action").put("message", "User must open Portal pending actions; this has NOT been executed")
    }
    fun launch(activity: Activity, id: String) {
        val row = store.get("actions", id) ?: error("Action not found")
        check(row.getString("status") == "pending_user_action") { "Action already handled" }
        check(Instant.parse(row.getString("created")).plusSeconds(86400).isAfter(Instant.now())) { "Action expired" }
        AndroidPortalPolicy.requireAccess(context, owner, row.getString("kind"), true)
        activity.startActivity(intent(row.getString("kind"), row.getJSONObject("arguments")))
        store.put("actions", row.put("status", "handed_to_system_unconfirmed"))
        context.getSystemService(android.app.NotificationManager::class.java).cancel(id.hashCode())
        store.activity("${row.getString("kind")}.launch", "handed_to_system_unconfirmed")
    }
    fun cancel(id: String) {
        val row = store.get("actions", id) ?: error("Action not found")
        check(row.getString("status") in listOf("pending_user_action", "cancelled")) { "Action already handed to system; cannot undo it" }
        store.put("actions", row.put("status", "cancelled"))
        context.getSystemService(android.app.NotificationManager::class.java).cancel(id.hashCode())
    }
    companion object {
        fun intent(kind: String, args: JSONObject): Intent = when (kind) {
            "phone" -> {
                val number = args.text("number", 40)
                require(Regex("[+0-9 ()-]{1,40}").matches(number)) { "Invalid phone number" }
                Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", number, null))
            }
            "clock" -> when (args.getString("action")) {
                "alarm" -> {
                    val hour = args.getInt("hour"); val minute = args.getInt("minute")
                    require(hour in 0..23 && minute in 0..59)
                    Intent(AlarmClock.ACTION_SET_ALARM).putExtra(AlarmClock.EXTRA_HOUR, hour).putExtra(AlarmClock.EXTRA_MINUTES, minute)
                        .putExtra(AlarmClock.EXTRA_MESSAGE, args.text("title", 200)).putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                }
                "timer" -> {
                    val seconds = args.getInt("seconds"); require(seconds in 1..86400)
                    Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH, seconds).putExtra(AlarmClock.EXTRA_MESSAGE, args.text("title", 200)).putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                }
                "show" -> Intent(AlarmClock.ACTION_SHOW_ALARMS)
                else -> error("Unknown clock action")
            }
            else -> error("Unknown system action")
        }
    }
}

class AndroidPortalActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val owner = AndroidPortalPolicy.owner(this); val id = intent.getStringExtra("action_id")
        if (owner.isEmpty() || id == null) { startActivity(Intent(this, MainActivity::class.java).putExtra("open_portal", true)); finish(); return }
        val row = AndroidPortalStore(this, owner).get("actions", id)
        if (row == null) { finish(); return }
        AlertDialog.Builder(this).setTitle("打开系统应用处理")
            .setMessage("${row.optString("kind")}\n${row.optJSONObject("arguments")}")
            .setPositiveButton("继续") { _, _ ->
                runCatching { AndroidPortalActions(this, owner).launch(this, id) }
                    .onFailure { android.widget.Toast.makeText(this, "操作未完成：权限已关闭、操作过期或缺少系统应用。", android.widget.Toast.LENGTH_LONG).show() }
                finish()
            }.setNegativeButton("取消操作") { _, _ -> AndroidPortalActions(this, owner).cancel(id); finish() }
            .setOnCancelListener { finish() }.show()
    }
}
