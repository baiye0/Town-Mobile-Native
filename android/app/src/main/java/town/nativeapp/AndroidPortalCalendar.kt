package town.nativeapp

import android.Manifest
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.provider.CalendarContract as C
import org.json.JSONObject
import java.time.ZoneId

class AndroidPortalCalendar(private val context: Context) {
    private val resolver get() = context.contentResolver
    fun call(action: String, args: JSONObject): JSONObject {
        AndroidPortalPolicy.permission(context, Manifest.permission.READ_CALENDAR)
        if (action !in listOf("calendars", "search", "get")) AndroidPortalPolicy.permission(context, Manifest.permission.WRITE_CALENDAR)
        return when (action) {
            "calendars" -> {
                val rows = mutableListOf<JSONObject>()
                resolver.query(C.Calendars.CONTENT_URI, arrayOf("_id", "calendar_displayName", "calendar_access_level"), null, null, "_id ASC")?.use { c ->
                    while (c.moveToNext() && rows.size < 100) rows += JSONObject().put("id", c.getLong(0)).put("name", c.getString(1)).put("writable", c.getInt(2) >= C.Calendars.CAL_ACCESS_CONTRIBUTOR)
                }
                JSONObject().put("calendars", jsonArray(rows))
            }
            "search" -> {
                val (start, end) = AndroidPortalRules.interval(args)
                val builder = C.Instances.CONTENT_URI.buildUpon(); ContentUris.appendId(builder, start); ContentUris.appendId(builder, end)
                val rows = mutableListOf<JSONObject>(); val query = args.text("query", required = false)
                val selection = if (args.has("calendar_id")) "calendar_id=?" else null
                resolver.query(builder.build(), arrayOf("event_id", "calendar_id", "title", "begin", "end", "eventLocation", "allDay"), selection,
                    selection?.let { arrayOf(args.getLong("calendar_id").toString()) }, "begin ASC")?.use { c ->
                    while (c.moveToNext() && rows.size < 200) if (query.isEmpty() || c.getString(2).orEmpty().contains(query, true)) {
                        rows += JSONObject().put("id", c.getLong(0)).put("calendar_id", c.getLong(1)).put("title", c.getString(2))
                            .put("start", java.time.Instant.ofEpochMilli(c.getLong(3))).put("end", java.time.Instant.ofEpochMilli(c.getLong(4)))
                            .put("location", c.getString(5)).put("all_day", c.getInt(6) == 1)
                    }
                }
                JSONObject().put("events", jsonArray(rows)).put("limit", 200)
            }
            "get" -> get(args.getLong("id"))
            "create", "update" -> {
                val (start, end) = AndroidPortalRules.interval(args)
                val zone = args.optString("timezone", ZoneId.systemDefault().id); ZoneId.of(zone)
                val allDay = args.optBoolean("all_day")
                if (allDay) require(start % 86400000L == 0L && end % 86400000L == 0L) { "All-day dates must use UTC midnight, end exclusive" }
                val calendarId = if (action == "update") get(args.getLong("id")).getLong("calendar_id") else args.getLong("calendar_id")
                requireWritable(calendarId)
                val recurrence = AndroidPortalRules.recurrence(args.optString("recurrence"))
                val values = ContentValues().apply {
                    put(C.Events.CALENDAR_ID, calendarId); put(C.Events.TITLE, args.text("title", 300))
                    put(C.Events.DESCRIPTION, args.text("description", 4000, false)); put(C.Events.EVENT_LOCATION, args.text("location", 500, false))
                    put(C.Events.DTSTART, start); put(C.Events.EVENT_TIMEZONE, if (allDay) "UTC" else zone); put(C.Events.ALL_DAY, if (allDay) 1 else 0)
                    put(C.Events.RRULE, recurrence)
                    if (recurrence == null) { put(C.Events.DTEND, end); putNull(C.Events.DURATION) }
                    else { putNull(C.Events.DTEND); put(C.Events.DURATION, if (allDay) "P${(end-start)/86400000}D" else "PT${(end-start)/1000}S") }
                }
                val minutes = args.optInt("reminder_minutes", -1)
                require(minutes in -1..40320) { "Invalid reminder_minutes" }
                val operations = arrayListOf<ContentProviderOperation>()
                val id = if (action == "update") args.getLong("id") else null
                if (id == null) operations += ContentProviderOperation.newInsert(C.Events.CONTENT_URI).withValues(values).build()
                else {
                    operations += ContentProviderOperation.newUpdate(ContentUris.withAppendedId(C.Events.CONTENT_URI, id)).withValues(values).withExpectedCount(1).build()
                    operations += ContentProviderOperation.newDelete(C.Reminders.CONTENT_URI).withSelection("event_id=?", arrayOf(id.toString())).build()
                }
                if (minutes >= 0) {
                    val reminder = ContentProviderOperation.newInsert(C.Reminders.CONTENT_URI).withValue(C.Reminders.MINUTES, minutes).withValue(C.Reminders.METHOD, C.Reminders.METHOD_ALERT)
                    if (id == null) reminder.withValueBackReference(C.Reminders.EVENT_ID, 0) else reminder.withValue(C.Reminders.EVENT_ID, id)
                    operations += reminder.build()
                }
                val result = resolver.applyBatch(C.AUTHORITY, operations)
                val eventId = id ?: ContentUris.parseId(result[0].uri!!)
                get(eventId).put("status", "saved").put("scope", "whole_event_or_series")
            }
            "delete" -> {
                val id = args.getLong("id"); requireWritable(get(id).getLong("calendar_id"))
                check(resolver.delete(ContentUris.withAppendedId(C.Events.CONTENT_URI, id), null, null) == 1) { "Event not found" }
                JSONObject().put("id", id).put("status", "deleted").put("scope", "whole_event_or_series")
            }
            else -> error("Unknown calendar action")
        }
    }
    private fun requireWritable(id: Long) {
        resolver.query(ContentUris.withAppendedId(C.Calendars.CONTENT_URI, id), arrayOf(C.Calendars.CALENDAR_ACCESS_LEVEL), null, null, null)?.use {
            check(it.moveToFirst() && it.getInt(0) >= C.Calendars.CAL_ACCESS_CONTRIBUTOR) { "Calendar is not writable" }
        } ?: error("Calendar unavailable")
    }
    private fun get(id: Long): JSONObject {
        resolver.query(ContentUris.withAppendedId(C.Events.CONTENT_URI, id), arrayOf("_id", "calendar_id", "title", "dtstart", "dtend", "duration", "eventTimezone", "rrule", "allDay", "description", "eventLocation"), "deleted=0", null, null)?.use { c ->
            check(c.moveToFirst()) { "Event not found" }
            val reminders = mutableListOf<Int>()
            resolver.query(C.Reminders.CONTENT_URI, arrayOf(C.Reminders.MINUTES), "event_id=?", arrayOf(id.toString()), null)?.use { cursor -> while (cursor.moveToNext()) reminders += cursor.getInt(0) }
            return JSONObject().put("reminders_minutes", jsonArray(reminders)).put("id", c.getLong(0)).put("calendar_id", c.getLong(1)).put("title", c.getString(2))
                .put("start", java.time.Instant.ofEpochMilli(c.getLong(3)).toString())
                .put("end", if (c.isNull(4)) JSONObject.NULL else java.time.Instant.ofEpochMilli(c.getLong(4)).toString())
                .put("duration", c.getString(5)).put("timezone", c.getString(6)).put("recurrence", c.getString(7))
                .put("all_day", c.getInt(8) == 1).put("description", c.getString(9)).put("location", c.getString(10))
        }
        error("Calendar unavailable")
    }
}
