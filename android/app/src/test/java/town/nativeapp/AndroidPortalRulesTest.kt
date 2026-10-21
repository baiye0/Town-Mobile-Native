package town.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class AndroidPortalRulesTest {
    @Test fun intervalsRejectReversedAndUnboundedRanges() {
        val valid = JSONObject().put("start", "2026-10-21T07:00:00Z").put("end", "2026-10-21T08:00:00Z")
        assertEquals(3600000L, AndroidPortalRules.interval(valid).second - AndroidPortalRules.interval(valid).first)
        assertThrows(IllegalArgumentException::class.java) { AndroidPortalRules.interval(valid.put("end", "2026-10-20T08:00:00Z")) }
        assertThrows(IllegalArgumentException::class.java) { AndroidPortalRules.interval(valid.put("end", "2030-10-20T08:00:00Z")) }
    }
    @Test fun recurrenceIsBoundedAndCannotInjectFields() {
        assertEquals("FREQ=WEEKLY;INTERVAL=2;COUNT=12", AndroidPortalRules.recurrence("FREQ=WEEKLY;INTERVAL=2;COUNT=12"))
        assertNull(AndroidPortalRules.recurrence(""))
        assertThrows(IllegalArgumentException::class.java) { AndroidPortalRules.recurrence("FREQ=SECONDLY") }
        assertThrows(IllegalArgumentException::class.java) { AndroidPortalRules.recurrence("FREQ=DAILY\nDTSTART:20260101") }
    }
    @Test fun dailyReminderRetainsLocalTimeAcrossDaylightSaving() {
        val before = Instant.parse("2026-03-07T14:00:00Z").toEpochMilli() // 09:00 New York
        val next = AndroidPortalRules.nextReminder(before, "daily", "America/New_York", before)!!
        assertEquals("2026-03-08T13:00:00Z", Instant.ofEpochMilli(next).toString())
        assertEquals(23 * 3600000L, next - before)
    }
    @Test fun missedWeeklyRemindersSkipPastOccurrences() {
        val before = Instant.parse("2026-10-01T09:00:00Z").toEpochMilli()
        val now = Instant.parse("2026-10-21T10:00:00Z").toEpochMilli()
        assertEquals("2026-10-22T09:00:00Z", Instant.ofEpochMilli(AndroidPortalRules.nextReminder(before, "weekly", "UTC", now)!!).toString())
        assertNull(AndroidPortalRules.nextReminder(before, "none", "UTC", now))
    }
}
