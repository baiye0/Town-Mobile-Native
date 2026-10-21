package town.nativeapp

import android.Manifest
import org.junit.Assert.*
import org.junit.Test

class AndroidPortalPermissionsTest {
    @Test fun policySwitchCannotSubstituteForOsPermissions() {
        val phone = PortalPermissionSnapshot()
        assertEquals("required", phone.access("calendar", false).state)
        assertEquals("required", phone.access("contacts", true).state)
        assertEquals("required", phone.access("location", false).state)
    }

    @Test fun readGrantDoesNotAuthorizeWritesAndRevocationIsReflected() {
        val read = PortalPermissionSnapshot(granted = setOf(Manifest.permission.READ_CALENDAR, Manifest.permission.READ_CONTACTS))
        for (group in listOf("calendar", "contacts")) {
            assertEquals("granted", read.access(group, false).state)
            assertEquals("partial", read.access(group, true).state)
            assertEquals("required", read.copy(granted = emptySet()).access(group, false).state)
        }
    }

    @Test fun approximateLocationWorksInForegroundButCannotEnableGeofences() {
        val phone = PortalPermissionSnapshot(granted = setOf(Manifest.permission.ACCESS_COARSE_LOCATION), locationEnabled = true)
        assertEquals("granted", phone.access("location", false).state)
        assertTrue(phone.access("location", false).detail.contains("大致"))
        assertTrue(phone.access("location", false).detail.contains("前台"))
        assertEquals("required", phone.access("geofences", true).state)
        assertEquals("unavailable", phone.copy(locationEnabled = false).access("location", false).state)
    }

    @Test fun geofenceGuidesForegroundThenBackgroundThenNotificationsThenService() {
        val fine = PortalPermissionSnapshot(granted = setOf(Manifest.permission.ACCESS_FINE_LOCATION), locationEnabled = true)
        assertTrue(fine.access("geofences", true).detail.contains("第 2 步"))
        val background = fine.copy(granted = fine.granted + Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        assertTrue(background.access("geofences", true).detail.contains("第 3 步"))
        val notices = background.copy(notifications = true)
        assertEquals("unavailable", notices.access("geofences", true).state)
        assertEquals("granted", notices.copy(playServices = true).access("geofences", true).state)
    }

    @Test fun notificationAccessAndConnectionAreSeparate() {
        assertEquals("required", PortalPermissionSnapshot().access("notifications", false).state)
        assertEquals("unavailable", PortalPermissionSnapshot(listenerAllowed = true).access("notifications", false).state)
        assertEquals("granted", PortalPermissionSnapshot(listenerAllowed = true, listenerConnected = true).access("notifications", true).state)
    }

    @Test fun healthUnknownEmptyPartialFullAndUnavailableAreDistinct() {
        val phone = PortalPermissionSnapshot(healthAvailable = true)
        assertEquals("unknown", phone.access("health", false).state)
        assertEquals("required", phone.copy(healthGranted = 0).access("health", false).state)
        assertEquals("partial", phone.copy(healthGranted = 2).access("health", false).state)
        assertEquals("granted", phone.copy(healthGranted = 5).access("health", false).state)
        assertEquals("unavailable", phone.copy(healthAvailable = false, healthGranted = 5).access("health", false).state)
    }

    @Test fun localRecordsAndSystemHandoffsDoNotNeedUnrelatedPermissions() {
        val phone = PortalPermissionSnapshot()
        for (group in listOf("reminders", "geofences", "clock", "phone", "shares"))
            assertEquals("not_required", phone.access(group, false).state)
        assertEquals("required", phone.access("reminders", true).state)
    }
}
