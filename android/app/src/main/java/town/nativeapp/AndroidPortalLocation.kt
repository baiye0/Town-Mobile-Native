package town.nativeapp

import android.Manifest
import android.app.PendingIntent
import android.content.*
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Tasks
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class AndroidPortalLocation(private val context: Context, private val owner: String) {
    private val store = AndroidPortalStore(context, owner)
    fun current(): JSONObject {
        val fine = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!fine) AndroidPortalPolicy.permission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (!AndroidPortalPolicy.foreground && Build.VERSION.SDK_INT >= 29) AndroidPortalPolicy.permission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        val manager = context.getSystemService(LocationManager::class.java)
        val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER).firstOrNull {
            (it != LocationManager.GPS_PROVIDER || fine) && manager.isProviderEnabled(it)
        } ?: error("Location is disabled or no suitable provider is available")
        val latch = CountDownLatch(1); var location: Location? = null
        val listener = object : LocationListener {
            override fun onLocationChanged(value: Location) { location = value; latch.countDown() }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) { latch.countDown() }
            @Deprecated("Android legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        try {
            manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            check(latch.await(15, TimeUnit.SECONDS)) { "Location timed out; try outdoors or enable network location" }
            val value = location ?: error("Location unavailable")
            return JSONObject().put("latitude", value.latitude).put("longitude", value.longitude).put("accuracy_meters", value.accuracy)
                .put("time", Instant.ofEpochMilli(value.time).toString()).put("provider", value.provider)
        } finally { manager.removeUpdates(listener) }
    }
    private fun pending() = PendingIntent.getBroadcast(context, 0, Intent(context, AndroidPortalGeofenceReceiver::class.java)
        .setAction("town.nativeapp.PORTAL_GEOFENCE"), PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0))
    fun geofence(action: String, args: JSONObject): JSONObject {
        if (action == "list") return JSONObject().put("geofences", jsonArray(store.list("geofences"))).put("events", jsonArray(store.list("location_events")))
        if (action == "delete") {
            val id = args.text("id", 80)
            check(store.get("geofences", id) != null) { "Geofence not found" }
            ensureServices()
            Tasks.await(LocationServices.getGeofencingClient(context).removeGeofences(listOf("$owner/$id")), 15, TimeUnit.SECONDS)
            store.remove("geofences", id)
            return JSONObject().put("id", id).put("status", "deleted")
        }
        require(action in listOf("create", "update"))
        check(context.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()) { "Enable app notifications before creating location reminders" }
        AndroidPortalPolicy.permission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 29) AndroidPortalPolicy.permission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        val lat = args.getDouble("latitude"); val lon = args.getDouble("longitude"); val radius = args.optDouble("radius_meters", 200.0)
        require(lat in -90.0..90.0 && lon in -180.0..180.0 && radius in 100.0..10000.0) { "Invalid coordinates or radius (100–10000 meters)" }
        val transition = args.optString("transition", "enter"); require(transition in listOf("enter", "exit"))
        val id = if (action == "create") UUID.randomUUID().toString() else args.text("id", 80).also { check(store.get("geofences", it) != null) }
        val row = JSONObject().put("id", id).put("title", args.text("title", 200)).put("latitude", lat).put("longitude", lon)
            .put("radius_meters", radius).put("transition", transition).put("status", "registered")
        check(store.list("geofences").size < 20 || action == "update") { "Maximum 20 geofences per Being" }
        val previous = store.get("geofences", id); store.put("geofences", row)
        try { register(row) } catch (e: Exception) { if (previous == null) store.remove("geofences", id) else store.put("geofences", previous); throw e }
        return row.put("timing", "OS background delivery may be delayed")
    }
    private fun ensureServices() { check(GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS) { "Geofences require available Google Play services on this device" } }
    private fun register(row: JSONObject) {
        AndroidPortalPolicy.requireAccess(context, owner, "geofences", true)
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED) throw SecurityException("Precise location permission required")
        if (Build.VERSION.SDK_INT >= 29) AndroidPortalPolicy.permission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        ensureServices()
        val fence = Geofence.Builder().setRequestId("$owner/${row.getString("id")}")
            .setCircularRegion(row.getDouble("latitude"), row.getDouble("longitude"), row.getDouble("radius_meters").toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE).setTransitionTypes(if (row.getString("transition") == "enter") Geofence.GEOFENCE_TRANSITION_ENTER else Geofence.GEOFENCE_TRANSITION_EXIT).build()
        Tasks.await(LocationServices.getGeofencingClient(context).addGeofences(GeofencingRequest.Builder().setInitialTrigger(0).addGeofence(fence).build(), pending()), 15, TimeUnit.SECONDS)
    }
    fun restore() {
        if (!AndroidPortalPolicy.enabled(context, owner, "geofences", true)) return
        store.list("geofences").forEach { row -> runCatching { register(row); store.put("geofences", row.put("status", "registered")) }
            .onFailure { store.put("geofences", row.put("status", "restore_failed_check_permissions")) } }
    }
    fun removeRegistrations() {
        ensureServices()
        Tasks.await(LocationServices.getGeofencingClient(context).removeGeofences(pending()), 15, TimeUnit.SECONDS)
    }
}

class AndroidPortalGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        event.triggeringGeofences.orEmpty().forEach { fence ->
            val parts = fence.requestId.split('/'); if (parts.size != 2) return@forEach
            val owner = parts[0]; val id = parts[1]
            if (owner != AndroidPortalPolicy.owner(context) || !AndroidPortalPolicy.enabled(context, owner, "geofences", true)) return@forEach
            val store = AndroidPortalStore(context, owner); val row = store.get("geofences", id) ?: return@forEach
            if (store.list("location_events").size >= 100) store.remove("location_events", store.list("location_events").first().getString("id"))
            store.put("location_events", JSONObject().put("id", UUID.randomUUID().toString()).put("geofence_id", id)
                .put("transition", if (event.geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER) "enter" else "exit").put("time", Instant.now().toString()))
            AndroidPortalNotices.show(context, owner + id, row.getString("title"), "Being 地点提醒")
        }
    }
}
