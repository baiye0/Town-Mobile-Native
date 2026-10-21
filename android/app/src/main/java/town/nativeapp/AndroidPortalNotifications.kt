package town.nativeapp

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import org.json.JSONObject

class AndroidPortalNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() { current = this }
    override fun onListenerDisconnected() { if (current === this) current = null }
    override fun onDestroy() { if (current === this) current = null; super.onDestroy() }
    companion object { @Volatile var current: AndroidPortalNotificationListener? = null }
}

object AndroidPortalNotifications {
    fun call(context: Context, owner: String, action: String, args: JSONObject): JSONObject {
        val listener = AndroidPortalNotificationListener.current ?: error("Notification access not connected; enable in Android settings")
        val allowed = AndroidPortalPolicy.allowedApps(context, owner)
        val notifications = listener.activeNotifications.orEmpty().filter { it.packageName in allowed && it.packageName != context.packageName }
        if (action == "list") return JSONObject().put("notifications", jsonArray(notifications.take(100).map { entry ->
            val n = entry.notification
            JSONObject().put("id", entry.key).put("app", entry.packageName).put("title", n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.take(500))
                .put("text", (n.extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: n.extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.take(3000))
                .put("time", entry.postTime).put("actions", jsonArray(n.actions.orEmpty().mapIndexed { index, item ->
                    JSONObject().put("index", index).put("title", item.title.toString()).put("reply", item.remoteInputs?.any { it.allowFreeFormInput } == true)
                }))
        }))
        val entry = notifications.firstOrNull { it.key == args.text("id", 1000) } ?: error("Notification expired or app not allowed")
        when (action) {
            "dismiss" -> listener.cancelNotification(entry.key)
            "reply" -> {
                val item = entry.notification.actions?.getOrNull(args.getInt("action_index")) ?: error("Action unavailable")
                val input = item.remoteInputs?.firstOrNull { it.allowFreeFormInput } ?: error("This notification does not support text reply")
                val result = Bundle().apply { putCharSequence(input.resultKey, args.text("text", 2000)) }
                val intent = Intent(); RemoteInput.addResultsToIntent(arrayOf(input), intent, result)
                item.actionIntent.send(context, 0, intent)
            }
            else -> error("Supported notification actions: list, dismiss, reply")
        }
        return JSONObject().put("status", if (action == "reply") "reply_dispatched_delivery_unconfirmed" else "dismiss_requested")
    }
}
