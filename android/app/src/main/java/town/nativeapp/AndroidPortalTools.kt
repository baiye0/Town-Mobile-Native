package town.nativeapp

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.runBlocking

class AndroidPortalTools(private val context: Context, private val owner: String) {
    private val store = AndroidPortalStore(context, owner)
    private fun spec(group: String, description: String, actions: List<String>, fields: Map<String, String> = emptyMap()): JSONObject {
        val properties = JSONObject().put("action", JSONObject().put("type", "string").put("enum", jsonArray(actions)))
        fields.forEach { (name, detail) ->
            val parts = detail.split('|', limit = 2)
            properties.put(name, JSONObject().put("type", parts[0]).put("description", parts.getOrElse(1) { name }))
        }
        properties.put("request_id", JSONObject().put("type", "string").put("description", "Required unique ID for every write. Reuse only for retries with exactly the same arguments."))
        return JSONObject().put("name", "portal_android_$group").put("description", description)
            .put("inputSchema", JSONObject().put("type", "object").put("properties", properties).put("required", JSONArray().put("action")).put("additionalProperties", false))
    }
    private fun all(): List<JSONObject> = listOf(
        spec("capabilities", "Check per-Being native tool read/write grants and device availability. Never infer authorization from tool discovery.", listOf("get")),
        spec("calendar", "Android calendar. calendars lists IDs; search expands recurring instances (max 200); get reads event. Create/update require full title/start/end; update replaces fields and reminders for WHOLE series. Delete removes WHOLE series. ISO-8601 timestamps must include offset. All-day uses UTC midnight/end exclusive. Only writable calendars.", listOf("calendars", "search", "get", "create", "update", "delete"), mapOf("id" to "integer|Event ID", "calendar_id" to "integer|Writable calendar ID required for create", "query" to "string", "start" to "string|ISO-8601 instant", "end" to "string|ISO-8601 instant", "timezone" to "string|IANA timezone", "title" to "string", "description" to "string", "location" to "string", "all_day" to "boolean", "recurrence" to "string|FREQ=DAILY/WEEKLY/MONTHLY[;INTERVAL=N][;COUNT=N], empty for one-time", "reminder_minutes" to "integer|-1 none, 0..40320 before start")),
        spec("contacts", "Search contacts by name/phone; create local contact; update replaces name/phone/email on the specific raw contact, preserving other data. Delete removes that raw contact only.", listOf("search", "create", "update", "delete"), mapOf("query" to "string", "raw_contact_id" to "integer", "name" to "string", "phone" to "string", "email" to "string")),
        spec("reminders", "Manage Being-owned phone notifications. Survives Portal stop/reboot subject to OS settings. Default approximate; exact=true requires special access. Never claim exact delivery for approximate reminders. Update replaces the reminder. Dates need offset.", listOf("list", "create", "update", "delete"), mapOf("id" to "string", "title" to "string", "at" to "string|Future ISO-8601 instant", "timezone" to "string|IANA timezone for recurrence", "repeat" to "string|none/daily/weekly", "exact" to "boolean")),
        spec("clock", "Queue opening system Clock to create alarm/timer or show alarms. User must open pending action on phone. A queued/handed-off request is NOT proof an alarm was saved. Cannot enumerate system alarms.", listOf("alarm", "timer", "show"), mapOf("title" to "string", "hour" to "integer|0..23", "minute" to "integer|0..59", "seconds" to "integer|1..86400")),
        spec("phone", "Queue opening phone dialer. User initiates the call; no call is placed automatically.", listOf("dial"), mapOf("number" to "string|Phone number, no USSD/control codes")),
        spec("notifications", "Read only current notifications from user-selected apps, not complete chats. Dismiss or reply through provided remote input action. Reply dispatch is not delivery confirmation. Notification access required.", listOf("list", "dismiss", "reply"), mapOf("id" to "string|Notification key", "action_index" to "integer|Reply action index returned by list", "text" to "string")),
        spec("location", "Get a fresh phone location with accuracy and timestamp. Requires location grant, and background location when app is not visible. Can time out indoors.", listOf("get")),
        spec("geofences", "Create/update/delete phone location reminders, list fences and recent events. Google Play services, precise and background location required. radius 100..10000 meters. Updates replace all fields. Delivery may be delayed by system.", listOf("list", "create", "update", "delete"), mapOf("id" to "string", "title" to "string", "latitude" to "number", "longitude" to "number", "radius_meters" to "number", "transition" to "string|enter/exit")),
        spec("health", "Read authorized Health Connect steps, sleep, exercise, heart_rate, weight (max31 days/query). App must be open. No write, no inferred zero from missing data. Requires existing provider records. Paginate using returned next_page_token.", listOf("read"), mapOf("type" to "string|steps/sleep/exercise/heart_rate/weight", "start" to "string", "end" to "string", "page_token" to "string")),
        spec("shares", "List/read/delete items explicitly shared into Being. Files are workspace-relative; reading attachment bytes additionally requires workspace file permission. Deleting inbox item does not delete imported files.", listOf("list", "get", "delete"), mapOf("id" to "string")),
        spec("actions", "List/get/cancel pending phone UI handoffs. pending_user_action and handed_to_system_unconfirmed never mean call/alarm completed.", listOf("list", "get", "cancel"), mapOf("id" to "string")),
        spec("activity", "Read last100 native operation outcomes (no sensitive arguments or data).", listOf("list"))
    )
    fun list(): JSONArray {
        check(owner == AndroidPortalPolicy.owner(context)) { "Being identity changed" }
        return jsonArray(all().filter { spec ->
            val group = spec.getString("name").removePrefix("portal_android_")
            group in listOf("capabilities", "actions", "activity") || AndroidPortalPolicy.enabled(context, owner, group) || AndroidPortalPolicy.enabled(context, owner, group, true)
        })
    }
    fun call(name: String, args: JSONObject): JSONObject {
        check(owner == AndroidPortalPolicy.owner(context)) { "Being identity changed; restart Portal" }
        val definition = all().firstOrNull { it.getString("name") == name } ?: error("Unknown Android tool")
        val schema = definition.getJSONObject("inputSchema").getJSONObject("properties")
        args.keys().forEach { require(schema.has(it)) { "Unknown argument: $it" } }
        val action = args.text("action", 30)
        val allowed = schema.getJSONObject("action").getJSONArray("enum")
        require((0 until allowed.length()).any { allowed.getString(it) == action }) { "Unknown action" }
        val group = name.removePrefix("portal_android_")
        val write = action in listOf("create", "update", "delete", "alarm", "timer", "show", "dial", "dismiss", "reply", "cancel")
        fun authorize() {
            check(owner == AndroidPortalPolicy.owner(context)) { "Being identity changed; restart Portal" }
            if (group in AndroidPortalPolicy.groups) AndroidPortalPolicy.requireAccess(context, owner, group, write)
        }
        authorize()
        fun execute(): JSONObject = when (group) {
            "capabilities" -> JSONObject().put("grants", jsonArray(AndroidPortalPolicy.groups.keys.map { key -> JSONObject().put("group", key)
                .put("read", AndroidPortalPolicy.enabled(context, owner, key)).put("write", AndroidPortalPolicy.enabled(context, owner, key, true)) }))
                .put("system_access", systemAccess())
                .put("authorization_note", "grants are per-Being policy only, not Android permissions. Check system_access; partial grants permit only the indicated subset. Provider/service constraints still apply.")
                .put("health_available", AndroidPortalHealth.available(context)).put("notification_listener_connected", AndroidPortalNotificationListener.current != null)
                .put("notification_apps", jsonArray(AndroidPortalPolicy.allowedApps(context, owner))).put("exact_alarms", AndroidPortalReminders.exactAvailable(context))
                .put("app_visible", AndroidPortalPolicy.foreground)
            "calendar" -> AndroidPortalCalendar(context).call(action, args)
            "contacts" -> AndroidPortalContacts(context).call(action, args)
            "reminders" -> AndroidPortalReminders(context, owner).call(action, args)
            "clock", "phone" -> AndroidPortalActions(context, owner).queue(group, args)
            "notifications" -> AndroidPortalNotifications.call(context, owner, action, args)
            "location" -> AndroidPortalLocation(context, owner).current()
            "geofences" -> AndroidPortalLocation(context, owner).geofence(action, args)
            "health" -> AndroidPortalHealth.call(context, args)
            "shares", "actions" -> when (action) {
                "list" -> JSONObject().put(group, jsonArray(store.list(group).map { row -> if (group == "shares") JSONObject().put("id", row.getString("id")).put("time", row.optString("time")).put("preview", row.optString("text").take(200)).put("files", row.optJSONArray("files")) else row }))
                "get" -> store.get(group, args.text("id", 80)) ?: error("Item not found")
                "cancel" -> { AndroidPortalActions(context, owner).cancel(args.text("id", 80)); JSONObject().put("status", "cancelled") }
                "delete" -> { store.remove(group, args.text("id", 80)); JSONObject().put("status", "deleted") }
                else -> error("Unknown action")
            }
            "activity" -> JSONObject().put("activity", jsonArray(store.list("activity")))
            else -> error("Unknown tool")
        }
        return try {
            val result = if (write) store.once("$name:${args.text("request_id", 100)}", args, ::authorize) { execute() } else execute()
            authorize()
            if (group != "activity") store.activity("$name.$action", "success")
            result
        } catch (e: Exception) { store.activity("$name.$action", "failed"); throw e }
    }
    private fun systemAccess(): JSONArray {
        val snapshot = runBlocking { AndroidPortalPermissions.withHealth(context, AndroidPortalPermissions.snapshot(context)) }
        return jsonArray(AndroidPortalPolicy.groups.keys.map { group ->
            fun access(write: Boolean): JSONObject = snapshot.access(group, write).let {
                JSONObject().put("state", it.state).put("detail", it.detail)
            }
            JSONObject().put("group", group).put("read", access(false)).put("write", access(true))
        })
    }
    fun safeError(error: Exception): JSONObject = JSONObject().put("code", when (error) {
        is SecurityException -> "permission_required"; is IllegalArgumentException -> "invalid_arguments"; is IllegalStateException -> "unavailable_or_denied"; else -> "operation_failed"
    }).put("message", when (error) {
        is IllegalArgumentException, is IllegalStateException -> error.message?.take(300) ?: "Invalid or unavailable operation"
        is SecurityException -> "Android permission denied or revoked; check Portal settings"
        else -> "Android operation failed; check permissions, provider availability and inputs"
    })
}
