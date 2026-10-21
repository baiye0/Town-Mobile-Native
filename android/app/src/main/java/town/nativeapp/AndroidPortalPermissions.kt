package town.nativeapp

import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

internal data class PortalSystemAccess(val state: String, val detail: String)

/** Actual OS state, independent of the per-Being policy switches. No data providers are queried. */
internal data class PortalPermissionSnapshot(
    val granted: Set<String> = emptySet(),
    val notifications: Boolean = false,
    val listenerAllowed: Boolean = false,
    val listenerConnected: Boolean = false,
    val locationEnabled: Boolean = false,
    val backgroundRequired: Boolean = true,
    val playServices: Boolean = false,
    val healthAvailable: Boolean = false,
    val healthGranted: Int? = null,
    val healthTotal: Int = 5,
) {
    fun access(group: String, write: Boolean): PortalSystemAccess {
        fun state(value: String, detail: String) = PortalSystemAccess(value, detail)
        fun permissions(vararg required: String): PortalSystemAccess {
            val count = required.count { it in granted }
            return when (count) {
                required.size -> state("granted", "已授权")
                0 -> state("required", "待系统授权")
                else -> state("partial", "部分授权，仍缺少所需权限")
            }
        }
        return when (group) {
            "calendar" -> if (write) permissions(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR) else permissions(Manifest.permission.READ_CALENDAR)
            "contacts" -> if (write) permissions(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS) else permissions(Manifest.permission.READ_CONTACTS)
            "reminders" -> if (!write) state("not_required", "读取已保存提醒无需额外权限") else if (notifications) state("granted", "通知已允许；精确提醒需另行授权") else state("required", "待允许 Being 发送通知")
            "notifications" -> when {
                !listenerAllowed -> state("required", "待授权通知访问")
                !listenerConnected -> state("unavailable", "通知访问已授权，等待系统连接")
                else -> state("granted", "通知访问已授权；仅可访问下方勾选的应用")
            }
            "location" -> when {
                Manifest.permission.ACCESS_COARSE_LOCATION !in granted && Manifest.permission.ACCESS_FINE_LOCATION !in granted -> state("required", "待系统位置授权")
                !locationEnabled -> state("unavailable", "已授权，但手机定位开关关闭")
                else -> state("granted", "已授权${if (Manifest.permission.ACCESS_FINE_LOCATION in granted) "精确" else "大致"}位置${if (backgroundRequired && Manifest.permission.ACCESS_BACKGROUND_LOCATION !in granted) "，仅应用在前台时可用" else "，允许后台读取"}")
            }
            "geofences" -> when {
                !write -> state("not_required", "读取已保存地点提醒无需额外权限")
                Manifest.permission.ACCESS_FINE_LOCATION !in granted -> state("required", "待授权精确位置（第 1 步）")
                backgroundRequired && Manifest.permission.ACCESS_BACKGROUND_LOCATION !in granted -> state("partial", "待设置位置为“始终允许”（第 2 步）")
                !notifications -> state("partial", "待允许 Being 发送通知（第 3 步）")
                !locationEnabled -> state("unavailable", "权限已授予，但手机定位开关关闭")
                !playServices -> state("unavailable", "权限已授予，但 Google Play 服务不可用")
                else -> state("granted", "所需权限已授予；后台触发仍受系统限制")
            }
            "health" -> when {
                !healthAvailable -> state("unavailable", "Health Connect 不可用")
                healthGranted == null -> state("unknown", "健康权限待核实，请刷新")
                healthGranted == 0 -> state("required", "待系统健康数据授权")
                healthGranted < healthTotal -> state("partial", "部分授权（$healthGranted/$healthTotal 类），仅可读取已授权类别")
                else -> state("granted", "已授权 $healthTotal 类健康数据，仅应用在前台时读取")
            }
            "clock", "phone" -> state("not_required", "无需额外权限；需在手机确认并交给系统应用")
            else -> state("not_required", "无需额外系统权限")
        }
    }
}

internal object AndroidPortalPermissions {
    private val runtime get() = buildList {
        addAll(listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR,
        Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS, Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.ACCESS_FINE_LOCATION))
        if (Build.VERSION.SDK_INT >= 29) add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }

    fun snapshot(context: Context): PortalPermissionSnapshot {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = manager.getNotificationChannel("portal-events")
        return PortalPermissionSnapshot(
            granted = runtime.filter { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }.toSet(),
            notifications = manager.areNotificationsEnabled() && channel?.importance != NotificationManager.IMPORTANCE_NONE,
            listenerAllowed = manager.isNotificationListenerAccessGranted(ComponentName(context, AndroidPortalNotificationListener::class.java)),
            listenerConnected = AndroidPortalNotificationListener.current != null,
            locationEnabled = context.getSystemService(LocationManager::class.java).isLocationEnabled,
            backgroundRequired = Build.VERSION.SDK_INT >= 29,
            playServices = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS,
            healthAvailable = AndroidPortalHealth.available(context),
        )
    }

    suspend fun withHealth(context: Context, snapshot: PortalPermissionSnapshot): PortalPermissionSnapshot {
        if (!snapshot.healthAvailable) return snapshot
        val count = runCatching { HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions()
            .count { it in AndroidPortalHealth.permissions } }.getOrNull()
        return snapshot.copy(healthGranted = count)
    }
}
