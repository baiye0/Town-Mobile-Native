package town.nativeapp

import android.app.Instrumentation
import android.content.ContentUris
import android.content.ContentValues
import android.provider.CalendarContract as C
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

/** Runs only against the isolated QA package, synthetic calendar/contact, and owned reminders. */
object AndroidNativePortalQa {
    fun run(test: Instrumentation, tool: (String, JSONObject) -> JSONObject): List<String> {
        val context = test.targetContext
        check(context.packageName.endsWith(".portalqa"))
        val owner = AndroidPortalPolicy.owner(context)
        val store = AndroidPortalStore(context, owner)
        val passed = mutableListOf<String>()
        fun shell(command: String) = test.uiAutomation.executeShellCommand(command).use {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(it).use { input -> input.readBytes().toString(Charsets.UTF_8) }
        }
        fun args(action: String) = JSONObject().put("action", action).put("request_id", UUID.randomUUID().toString())
        fun call(group: String, value: JSONObject): JSONObject {
            val response = tool("portal_android_$group", value)
            check(!response.has("error") && response.optJSONObject("result")?.optBoolean("isError") != true) { "Native $group failed: $response" }
            return response.getJSONObject("result").getJSONObject("structuredContent")
        }
        fun denied(group: String, value: JSONObject) {
            val response = tool("portal_android_$group", value)
            check(response.has("error") || response.optJSONObject("result")?.optBoolean("isError") == true) { "Native $group unexpectedly allowed" }
        }
        val tag = "Portal QA ${UUID.randomUUID()}"
        var calendarId: Long? = null; var contactId: Long? = null
        val calendarUri = C.Calendars.CONTENT_URI.buildUpon().appendQueryParameter(C.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(C.Calendars.ACCOUNT_NAME, tag).appendQueryParameter(C.Calendars.ACCOUNT_TYPE, C.ACCOUNT_TYPE_LOCAL).build()
        val existingGrants = AndroidPortalPolicy.groups.keys.associateWith { AndroidPortalPolicy.enabled(context, owner, it) to AndroidPortalPolicy.enabled(context, owner, it, true) }
        val existingApps = AndroidPortalPolicy.allowedApps(context, owner)
        val listener = "${context.packageName}/town.nativeapp.AndroidPortalNotificationListener"
        val listenerWasEnabled = android.provider.Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners").orEmpty().contains(listener)
        fun await(label: String, condition: () -> Boolean) { repeat(100) { if (condition()) return; Thread.sleep(100) }; error("Timed out: $label") }
        val fixture = "${test.context.packageName}/town.nativeapp.PortalNotificationFixture"
        val emulator = android.os.Build.MODEL.startsWith("sdk_gphone")
        try {
            AndroidPortalPolicy.groups.keys.forEach { AndroidPortalPolicy.set(context, owner, it, false, false); AndroidPortalPolicy.set(context, owner, it, true, false) }
            denied("calendar", args("search").put("start", Instant.now().toString()).put("end", Instant.now().plusSeconds(3600).toString()))
            call("capabilities", args("get"))
            AndroidPortalBridge(context, owner).use { bridge ->
                java.net.Socket("127.0.0.1", bridge.port).use { socket ->
                    socket.soTimeout = 3000
                    socket.getOutputStream().write("{\"token\":\"invalid\",\"method\":\"list\"}\n".toByteArray())
                    check(socket.getInputStream().read() == -1)
                }
            }
            passed += "Native MCP bridge authentication and disabled capability enforcement"
            AndroidPortalBridge(context, owner).use { bridge ->
                java.net.Socket("127.0.0.1", bridge.port).use { socket ->
                    socket.soTimeout = 3500
                    val started = System.nanoTime()
                    val trickle = Thread {
                        while (!socket.isClosed) {
                            if (runCatching { socket.getOutputStream().write(' '.code); Thread.sleep(150) }.isFailure) break
                        }
                    }.apply { isDaemon = true; start() }
                    try {
                        check(socket.getInputStream().read() == -1) { "Slow unauthenticated peer must be closed" }
                        check((System.nanoTime() - started) / 1_000_000 < 3000) { "Request deadline was extended by trickling bytes" }
                    } finally { socket.close(); trickle.interrupt(); trickle.join(1000) }
                }
            }
            passed += "Native bridge enforces a total authentication deadline against trickling clients"
            val engine = AndroidPortalTools(context, owner)
            val shareId = UUID.randomUUID().toString()
            store.put("shares", JSONObject().put("id", shareId).put("text", "synthetic queued write target"))
            fun queuedWrite(changeAuthorization: () -> Unit) {
                val entered = java.util.concurrent.CountDownLatch(1)
                val release = java.util.concurrent.CountDownLatch(1)
                val failure = java.util.concurrent.atomic.AtomicReference<Throwable?>()
                val locker = Thread { store.once("qa-lock:${UUID.randomUUID()}", JSONObject(), {}) {
                    entered.countDown(); check(release.await(10, java.util.concurrent.TimeUnit.SECONDS)); JSONObject()
                } }
                val writer = Thread {
                    try { engine.call("portal_android_shares", args("delete").put("id", shareId)) }
                    catch (e: Throwable) { failure.set(e) }
                }
                try {
                    locker.start(); check(entered.await(5, java.util.concurrent.TimeUnit.SECONDS))
                    writer.start()
                    await("write queued on operation lock") {
                        writer.state == Thread.State.BLOCKED && writer.stackTrace.any { it.className.endsWith("AndroidPortalStore") && it.methodName == "once" }
                    }
                    changeAuthorization(); release.countDown(); writer.join(5000)
                    check(!writer.isAlive && failure.get() != null && store.get("shares", shareId) != null) { "Queued write bypassed changed authorization" }
                } finally { release.countDown(); locker.join(1000); writer.join(1000) }
            }
            AndroidPortalPolicy.set(context, owner, "shares", true, true)
            queuedWrite { AndroidPortalPolicy.set(context, owner, "shares", true, false) }
            AndroidPortalPolicy.set(context, owner, "shares", true, true)
            val savedIdentity = Vault(context).load()
            try { queuedWrite { Vault(context).save("https://127.0.0.1/queued-other/?token=synthetic") } }
            finally { Vault(context).save(savedIdentity); store.remove("shares", shareId) }
            passed += "Queued writes recheck revoked policy and changed Being before mutating data"
            AndroidPortalPolicy.set(context, owner, "phone", true, true)
            val queued = engine.call("portal_android_phone", args("dial").put("number", "5550100"))
            for (index in 1..99) store.put("actions", JSONObject().put("id", "qa-history-$index").put("status", "cancelled"))
            val next = engine.call("portal_android_phone", args("dial").put("number", "5550101"))
            check(store.list("actions").size == 100 && store.get("actions", queued.getString("id")) != null && store.get("actions", next.getString("id")) != null)
            store.list("actions").filter { it.optString("status") == "cancelled" }.forEach { store.remove("actions", it.getString("id")) }
            AndroidPortalActions(context, owner).cancel(queued.getString("id"))
            AndroidPortalActions(context, owner).cancel(next.getString("id"))
            passed += "Full action history prunes settled entries while retaining pending handoffs"
            for (permission in listOf("READ_CALENDAR", "WRITE_CALENDAR", "READ_CONTACTS", "WRITE_CONTACTS", "POST_NOTIFICATIONS")) shell("pm grant ${context.packageName} android.permission.$permission")
            for (group in listOf("calendar", "contacts", "reminders", "phone", "clock", "shares")) {
                AndroidPortalPolicy.set(context, owner, group, false, true); AndroidPortalPolicy.set(context, owner, group, true, true)
            }
            calendarId = ContentUris.parseId(context.contentResolver.insert(calendarUri, ContentValues().apply {
                put(C.Calendars.ACCOUNT_NAME, tag); put(C.Calendars.ACCOUNT_TYPE, C.ACCOUNT_TYPE_LOCAL); put(C.Calendars.NAME, tag)
                put(C.Calendars.CALENDAR_DISPLAY_NAME, tag); put(C.Calendars.CALENDAR_COLOR, -16776961); put(C.Calendars.CALENDAR_ACCESS_LEVEL, C.Calendars.CAL_ACCESS_OWNER)
                put(C.Calendars.OWNER_ACCOUNT, tag); put(C.Calendars.VISIBLE, 1); put(C.Calendars.SYNC_EVENTS, 1); put(C.Calendars.CALENDAR_TIME_ZONE, "Asia/Shanghai")
            })!!)
            val start = Instant.now().plusSeconds(3600); val end = start.plusSeconds(1800)
            val create = args("create").put("calendar_id", calendarId).put("title", tag).put("start", start.toString()).put("end", end.toString()).put("timezone", "Asia/Shanghai").put("recurrence", "FREQ=DAILY;COUNT=3").put("reminder_minutes", 15)
            val event = call("calendar", create); val eventId = event.getLong("id")
            check(event.getJSONArray("reminders_minutes").getInt(0) == 15)
            check(call("calendar", create).getLong("id") == eventId) // Retry cannot duplicate an event.
            denied("calendar", JSONObject(create.toString()).put("title", "changed retry"))
            val events = call("calendar", args("search").put("calendar_id", calendarId).put("start", start.minusSeconds(60).toString()).put("end", end.plusSeconds(3*86400).toString())).getJSONArray("events")
            check(events.length() == 3) { "Expected three recurring instances: $events" }
            call("calendar", args("update").put("id", eventId).put("title", "$tag updated").put("start", start.toString()).put("end", end.toString()))
            check(call("calendar", args("get").put("id", eventId)).getString("title").endsWith("updated"))
            call("calendar", args("delete").put("id", eventId)); denied("calendar", args("get").put("id", eventId))
            passed += "Real Android calendar CRUD, recurring instances, write idempotency and retry conflict"
            val contact = call("contacts", args("create").put("name", tag).put("phone", "5550100").put("email", "portal-qa@example.invalid"))
            contactId = contact.getLong("raw_contact_id")
            check(call("contacts", args("search").put("query", tag)).getJSONArray("contacts").length() > 0)
            call("contacts", args("update").put("raw_contact_id", contactId).put("name", tag).put("phone", "5550101"))
            check(call("contacts", args("search").put("query", tag)).toString().contains("5550101"))
            call("contacts", args("delete").put("raw_contact_id", contactId)); contactId = null
            check(call("contacts", args("search").put("query", tag)).getJSONArray("contacts").length() == 0)
            passed += "Real Android contacts create/search/update/delete, synthetic raw contact only"
            val reminder = call("reminders", args("create").put("title", tag).put("at", Instant.now().plusSeconds(600).toString()))
            val id = reminder.getString("id")
            check(reminder.getString("timing").contains("approximate"))
            call("reminders", args("update").put("id", id).put("title", tag).put("at", Instant.now().plusSeconds(1200).toString()))
            // An old delivered broadcast cannot fire a newly rescheduled reminder early.
            AndroidPortalReminders(context, owner).fire(id)
            check(store.get("reminders", id)!!.getString("status") == "scheduled")
            AndroidPortalReminders(context, owner).restore()
            call("reminders", args("delete").put("id", id))
            check(store.get("reminders", id) == null)
            passed += "Reminder scheduling/update/restore/delete and stale-broadcast suppression"
            val delivered = call("reminders", args("create").put("title", tag).put("at", Instant.now().plusSeconds(600).toString()))
            val deliveredId = delivered.getString("id")
            store.put("reminders", store.get("reminders", deliveredId)!!.put("at", Instant.now().minusSeconds(1).toString()))
            context.sendBroadcast(android.content.Intent(context, AndroidPortalReminderReceiver::class.java).setAction("town.nativeapp.PORTAL_REMINDER").putExtra("owner", owner).putExtra("id", deliveredId))
            await("reminder delivery") { store.get("reminders", deliveredId)?.optString("status") == "delivered" }
            check(context.getSystemService(android.app.NotificationManager::class.java).activeNotifications.any { it.id == (owner + deliveredId).hashCode() })
            call("reminders", args("delete").put("id", deliveredId))
            passed += "Reminder broadcast receiver delivers a real Android notification and records delivery"
            val dial = call("phone", args("dial").put("number", "5550100"))
            check(dial.getString("status") == "pending_user_action")
            call("actions", args("cancel").put("id", dial.getString("id")))
            check(call("actions", args("get").put("id", dial.getString("id"))).getString("status") == "cancelled")
            val alarm = call("clock", args("alarm").put("title", tag).put("hour", 8).put("minute", 0))
            check(alarm.getString("status") == "pending_user_action")
            call("actions", args("cancel").put("id", alarm.getString("id")))
            denied("phone", args("dial").put("number", "*123#"))
            passed += "Dialer/clock handoff stays pending until user action; cancellation and invalid number rejection"
            val sharedId = UUID.randomUUID().toString()
            store.put("shares", JSONObject().put("id", sharedId).put("text", "Synthetic shared meeting at 15:00").put("time", Instant.now().toString()))
            check(call("shares", args("get").put("id", sharedId)).getString("text").contains("15:00"))
            call("shares", args("delete").put("id", sharedId))
            passed += "Share inbox native MCP read/delete and per-Being storage"
            shell("am start -n ${context.packageName}/town.nativeapp.AndroidPortalShareActivity -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT Synthetic_Portal_share")
            await("share confirmation") { test.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText("分享给当前 Being")?.isNotEmpty() == true }
            val confirm = test.uiAutomation.rootInActiveWindow.findAccessibilityNodeInfosByText("接收").firstOrNull() ?: error("Share confirmation button missing")
            check(confirm.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
            await("share stored") { store.list("shares").any { it.optString("text") == "Synthetic_Portal_share" } }
            val shared = store.list("shares").first { it.optString("text") == "Synthetic_Portal_share" }
            check(call("shares", args("get").put("id", shared.getString("id"))).getString("text") == "Synthetic_Portal_share")
            call("shares", args("delete").put("id", shared.getString("id")))
            passed += "Real ACTION_SEND share activity, local user confirmation, and MCP inbox retrieval"
            for (group in listOf("health", "location", "geofences", "notifications")) {
                denied(group, when(group) { "health" -> args("read").put("type", "steps").put("start", start.toString()).put("end", end.toString()); "location" -> args("get"); else -> args("list") })
            }
            AndroidPortalPolicy.set(context, owner, "health", false, true)
            denied("health", args("read").put("type", "steps").put("start", Instant.now().minusSeconds(86400).toString()).put("end", Instant.now().toString()))
            AndroidPortalPolicy.set(context, owner, "geofences", false, true)
            check(call("geofences", args("list")).getJSONArray("geofences").length() == 0)
            passed += "Health/location/notification denial and geofence inventory without reading personal data"
            AndroidPortalPolicy.set(context, owner, "notifications", false, true)
            AndroidPortalPolicy.set(context, owner, "notifications", true, true)
            AndroidPortalPolicy.setApps(context, owner, setOf(test.context.packageName))
            shell("cmd notification allow_listener $listener")
            await("notification listener") { AndroidPortalNotificationListener.current != null }
            shell("pm grant ${test.context.packageName} android.permission.POST_NOTIFICATIONS")
            check(shell("am broadcast -n $fixture -a fixture.post").contains("posted"))
            var notification: JSONObject? = null
            await("fixture notification") {
                val notifications = call("notifications", args("list")).getJSONArray("notifications")
                notification = (0 until notifications.length()).map { notifications.getJSONObject(it) }.firstOrNull { it.optString("app") == test.context.packageName }
                notification != null
            }
            val key = notification!!.getString("id")
            AndroidPortalPolicy.setApps(context, owner, emptySet())
            check(call("notifications", args("list")).getJSONArray("notifications").length() == 0)
            denied("notifications", args("reply").put("id", key).put("action_index", 0).put("text", "blocked"))
            AndroidPortalPolicy.setApps(context, owner, setOf(test.context.packageName))
            val reply = args("reply").put("id", key).put("action_index", 0).put("text", "synthetic_reply_received")
            check(call("notifications", reply).getString("status") == "reply_dispatched_delivery_unconfirmed")
            await("RemoteInput received") { shell("am broadcast -n $fixture -a fixture.result").contains("synthetic_reply_received") }
            call("notifications", args("dismiss").put("id", key))
            await("notification dismissed") { call("notifications", args("list")).getJSONArray("notifications").length() == 0 }
            passed += "Real NotificationListener allowlist, RemoteInput reply delivered to fixture APK, and dismissal"
            if (emulator) {
                // The disposable emulator has no user location or health records.
                for (permission in listOf("READ_STEPS", "READ_SLEEP", "READ_EXERCISE", "READ_HEART_RATE", "READ_WEIGHT")) shell("pm grant ${context.packageName} android.permission.health.$permission")
                for (type in listOf("steps", "sleep", "exercise", "heart_rate", "weight")) {
                    val healthResult = call("health", args("read").put("type", type).put("start", Instant.now().minusSeconds(86400).toString()).put("end", Instant.now().toString()))
                    check(healthResult.getString("type") == type)
                }
                passed += "Health Connect actual provider queries for all five authorized types on empty disposable emulator"
                AndroidPortalPolicy.set(context, owner, "location", false, true)
                for (permission in listOf("ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION", "ACCESS_BACKGROUND_LOCATION")) shell("pm grant ${context.packageName} android.permission.$permission")
                shell("cmd location set-location-enabled true")
                shell("appops set com.android.shell android:mock_location allow")
                shell("cmd location providers add-test-provider network")
                shell("cmd location providers set-test-provider-enabled network true")
                val feeder = Thread { repeat(15) { shell("cmd location providers set-test-provider-location network --location 31.2304,121.4737 --accuracy 5"); Thread.sleep(300) } }.apply { start() }
                try {
                    val fix = call("location", args("get"))
                    check(kotlin.math.abs(fix.getDouble("latitude") - 31.2304) < 0.001)
                    check(fix.getDouble("accuracy_meters") <= 10)
                    AndroidPortalPolicy.set(context, owner, "geofences", true, true)
                    // A scheduled policy reconciliation must finish before the registration probe.
                    context.getSystemService(android.app.job.JobScheduler::class.java).cancel(7802)
                    val fenceResult = tool("portal_android_geofences", args("create").put("title", tag).put("latitude", 31.2304).put("longitude", 121.4737).put("radius_meters", 200))
                    if (fenceResult.optJSONObject("result")?.optBoolean("isError") == true || fenceResult.has("error")) {
                        check(store.list("geofences").isEmpty())
                        passed += "Geofence provider failure is reported and registration is rolled back (live GMS registration unavailable in emulator)"
                    } else {
                        val fenceId = fenceResult.getJSONObject("result").getJSONObject("structuredContent").getString("id")
                        check(call("geofences", args("list")).getJSONArray("geofences").length() == 1)
                        call("geofences", args("update").put("id", fenceId).put("title", tag).put("latitude", 31.2304).put("longitude", 121.4737).put("radius_meters", 250).put("transition", "exit"))
                        call("geofences", args("delete").put("id", fenceId))
                        check(store.list("geofences").isEmpty())
                        passed += "Actual Google Play geofence register/update/list/delete; physical arrival/exit remains a field test"
                    }
                } finally { feeder.join(); shell("cmd location providers remove-test-provider network"); shell("appops set com.android.shell android:mock_location default") }
                passed += "LocationManager delivers a fresh synthetic network location through the full MCP path"
            }
            val original = Vault(context).load()
            val originalWorkspace = PortalRuntime.workspace(context).root
            try { Vault(context).save("https://127.0.0.1/other-fixture/?token=synthetic"); denied("capabilities", args("get")); check(PortalRuntime.workspace(context).root != originalWorkspace) }
            finally { Vault(context).save(original) }
            passed += "Native bridge rejects identity changes without leaking previous Being data"
        } finally {
            shell("am broadcast -n $fixture -a fixture.clear")
            if (!listenerWasEnabled) shell("cmd notification disallow_listener $listener")
            AndroidPortalPolicy.setApps(context, owner, existingApps)
            calendarId?.let { context.contentResolver.delete(ContentUris.withAppendedId(calendarUri, it), null, null) }
            contactId?.let { context.contentResolver.delete(ContentUris.withAppendedId(android.provider.ContactsContract.RawContacts.CONTENT_URI, it), null, null) }
            store.list("reminders").forEach { runCatching { AndroidPortalReminders(context, owner).call("delete", JSONObject().put("id", it.getString("id"))) } }
            store.list("actions").forEach { context.getSystemService(android.app.NotificationManager::class.java).cancel(it.getString("id").hashCode()); store.remove("actions", it.getString("id")) }
            existingGrants.forEach { (group, grant) -> AndroidPortalPolicy.set(context, owner, group, false, grant.first); AndroidPortalPolicy.set(context, owner, group, true, grant.second) }
        }
        return passed
    }
}
