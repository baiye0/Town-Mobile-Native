package town.nativeapp

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.ContextWrapper
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.PermissionController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

@Composable
fun AndroidPortalSettings() {
    val context = LocalContext.current
    val owner = AndroidPortalPolicy.owner(context)
    val scope = rememberCoroutineScope()
    var revision by remember { mutableIntStateOf(0) }
    var expanded by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var rows by remember(owner) { mutableStateOf<Map<String, List<JSONObject>>>(emptyMap()) }
    var selectedShare by remember { mutableStateOf<JSONObject?>(null) }
    var system by remember { mutableStateOf(AndroidPortalPermissions.snapshot(context)) }
    var pendingLabel by rememberSaveable { mutableStateOf("") }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        system = AndroidPortalPermissions.snapshot(context)
        revision++
        message = when {
            result.isEmpty() -> "$pendingLabel：未完成授权，请查看下方实际状态。"
            result.values.all { it } -> "$pendingLabel：本次请求的系统权限已授予。"
            result.values.any { it } -> "$pendingLabel：仅授予了部分权限，请查看下方状态。"
            else -> "$pendingLabel：系统权限未授予。若不再出现弹窗，请进入系统应用设置。"
        }
    }
    val health = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) {
        system = system.copy(healthGranted = null)
        revision++
        message = "健康授权页面已返回，请以下方实际系统状态为准；未授权类别不会读取。"
    }
    fun perform(action: () -> Unit) { scope.launch {
        try { withContext(Dispatchers.IO) { action() }; revision++ }
        catch (_: Exception) { message = "操作未完成，请检查权限、系统服务及当前连接。" }
    } }
    fun settings(action: String, packageUri: Boolean = false) {
        runCatching { context.startActivity(Intent(action).apply { if (packageUri) data = Uri.parse("package:${context.packageName}") }) }
            .onFailure { message = "此设备没有对应设置页面，请从系统应用设置进入。" }
    }
    fun request(label: String, permissions: List<String>) {
        val current = AndroidPortalPermissions.snapshot(context)
        val missing = permissions.filter { it !in current.granted }
        if (missing.isEmpty()) { system = current; revision++; return }
        val history = context.getSharedPreferences("portal_permission_requests", 0)
        val activity = generateSequence(context) { (it as? ContextWrapper)?.baseContext }.filterIsInstance<Activity>().firstOrNull()
        if (activity != null && missing.any { history.getBoolean(it, false) && !activity.shouldShowRequestPermissionRationale(it) }) {
            message = "$label：系统未提供授权弹窗，请在应用权限设置中允许；返回后将自动刷新。"
            settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true)
        } else {
            pendingLabel = label
            runCatching { permission.launch(permissions.toTypedArray()) }
                .onSuccess { history.edit().apply { missing.forEach { putBoolean(it, true) } }.apply() }
                .onFailure { message = "$label：无法打开系统授权，请从系统应用设置进入。" }
        }
    }
    fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33 && Manifest.permission.POST_NOTIFICATIONS !in AndroidPortalPermissions.snapshot(context).granted)
            request("提醒通知", listOf(Manifest.permission.POST_NOTIFICATIONS))
        else settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true)
    }
    fun authorize(key: String, write: Boolean) {
        val current = AndroidPortalPermissions.snapshot(context)
        when (key) {
            "calendar" -> request("日历", if (write) listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR) else listOf(Manifest.permission.READ_CALENDAR))
            "contacts" -> request("通讯录", if (write) listOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS) else listOf(Manifest.permission.READ_CONTACTS))
            "reminders" -> if (write && !current.notifications) requestNotifications()
            "notifications" -> if (!current.listenerAllowed) settings(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            "location" -> if (Manifest.permission.ACCESS_COARSE_LOCATION !in current.granted && Manifest.permission.ACCESS_FINE_LOCATION !in current.granted)
                request("位置", listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION))
                else if (!current.locationEnabled) settings(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "geofences" -> if (write) when {
                Manifest.permission.ACCESS_FINE_LOCATION !in current.granted -> request("地点提醒：精确位置", listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION))
                current.backgroundRequired && Manifest.permission.ACCESS_BACKGROUND_LOCATION !in current.granted -> {
                    message = "地点提醒需要后台定位，请将位置权限设为“始终允许”；返回后再继续授权。"
                    if (Build.VERSION.SDK_INT == 29) request("地点提醒：后台位置", listOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION))
                    else settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true)
                }
                !current.notifications -> requestNotifications()
                !current.locationEnabled -> settings(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                !current.playServices -> message = "此设备的 Google Play 服务不可用，暂时不能注册地点提醒。"
            }
            "health" -> runCatching {
                if (current.healthAvailable) health.launch(AndroidPortalHealth.permissions)
                else context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.google.android.apps.healthdata")))
            }.onFailure { message = "无法打开健康授权，请从系统 Health Connect 设置进入。" }
        }
        revision++
    }
    fun toggle(key: String, write: Boolean, value: Boolean) {
        AndroidPortalPolicy.set(context, owner, key, write, value)
        revision++
        message = if (value) "已允许当前 Being 使用此项能力；实际可用范围以下方系统状态为准。" else "已关闭当前 Being 的此项能力。系统权限可在手机设置中另行撤销。"
        if (value) authorize(key, write)
    }
    androidx.lifecycle.compose.LifecycleResumeEffect(owner) {
        system = AndroidPortalPermissions.snapshot(context)
        revision++
        onPauseOrDispose {}
    }
    LaunchedEffect(owner, revision) {
        system = AndroidPortalPermissions.withHealth(context, AndroidPortalPermissions.snapshot(context))
        if (owner.isNotEmpty()) rows = withContext(Dispatchers.IO) {
            val store = AndroidPortalStore(context, owner)
            listOf("actions", "reminders", "geofences", "shares", "activity").associateWith { store.list(it) }
        }
    }
    SettingsCard { Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SettingsHeading("手机原生能力", Icons.Outlined.PhoneAndroid, "日历、提醒、通知、位置与健康")
        Text("开关仅表示允许当前 Being 使用，开启时会引导手机系统授权。必须同时满足 Being 授权与系统权限，功能才可执行。读取结果会提供给该 Being；允许写入后，它可执行该类操作。", style = MaterialTheme.typography.bodySmall)
        Text("首次开启能力后请重启 Portal 刷新工具列表；关闭授权会立即拦截新调用。", style = MaterialTheme.typography.bodySmall)
        if (owner.isEmpty()) Text("请先连接 Being。")
        else {
            TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "收起授权设置" else "展开授权设置") }
            if (expanded) {
                AndroidPortalPolicy.groups.forEach { (key, label) ->
                    Text(label, style = MaterialTheme.typography.titleSmall)
                    if (key !in listOf("clock", "phone")) {
                        val read = remember(owner, revision, key) { AndroidPortalPolicy.enabled(context, owner, key) }
                        SettingsToggle("允许 Being 读取", read) { toggle(key, false, it) }
                        PortalPermissionStatus(read, system.access(key, false))
                    }
                    if (key !in listOf("health", "location")) {
                        val write = remember(owner, revision, key) { AndroidPortalPolicy.enabled(context, owner, key, true) }
                        SettingsToggle(if (key in listOf("clock", "phone")) "允许 Being 创建待处理操作" else "允许 Being 写入或操作", write) { toggle(key, true, it) }
                        PortalPermissionStatus(write, system.access(key, true))
                    }
                    when (key) {
                        "calendar", "contacts" -> TextButton(onClick = { authorize(key, AndroidPortalPolicy.enabled(context, owner, key, true)) }) { Text("继续系统授权") }
                        "reminders" -> {
                            Text("普通提醒可能延迟；精确提醒需系统授权。提醒独立于 Portal 服务，停止服务不取消已设提醒。切换 Being 后旧身份提醒暂停。", style = MaterialTheme.typography.bodySmall)
                            TextButton(onClick = { requestNotifications() }) { Text("设置通知权限") }
                            if (Build.VERSION.SDK_INT >= 31) TextButton(onClick = { settings(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, true) }) { Text("精确提醒权限：${if (AndroidPortalReminders.exactAvailable(context)) "已允许" else "未允许"}") }
                        }
                        "clock" -> Text("操作保存在下方待处理列表，需打开手机系统时钟；交给系统不代表已经保存闹钟。", style = MaterialTheme.typography.bodySmall)
                        "notifications" -> {
                            TextButton(onClick = { settings(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS) }) { Text("通知访问权限") }
                            Text("仅向 Being 提供勾选应用的当前通知；不能读取完整聊天记录。回复需要对方通知提供快捷回复按钮。", style = MaterialTheme.typography.bodySmall)
                            val apps = remember(owner, revision) { (runCatching { AndroidPortalNotificationListener.current?.activeNotifications.orEmpty().map { it.packageName } }.getOrDefault(emptyList()) + AndroidPortalPolicy.allowedApps(context, owner)).distinct().filter { it != context.packageName }.sorted() }
                            if (apps.isEmpty()) Text("授权后，先让目标应用产生一条通知，再点击刷新选择应用。", style = MaterialTheme.typography.bodySmall)
                            apps.forEach { app ->
                                val allowed = AndroidPortalPolicy.allowedApps(context, owner)
                                SettingsToggle(app, app in allowed) { selected -> AndroidPortalPolicy.setApps(context, owner, if (selected) allowed + app else allowed - app); revision++ }
                            }
                        }
                        "location" -> {
                            TextButton(onClick = { request("位置", listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)) }) { Text("设置位置精度") }
                            TextButton(onClick = { settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true) }) { Text("设置后台位置权限") }
                            if (!system.locationEnabled) TextButton(onClick = { settings(Settings.ACTION_LOCATION_SOURCE_SETTINGS) }) { Text("打开手机定位") }
                        }
                        "geofences" -> {
                            Text("地点提醒需要精确位置、始终允许位置与可用的 Google Play 服务；后台触发可能延迟。", style = MaterialTheme.typography.bodySmall)
                            TextButton(onClick = { authorize(key, true) }) { Text("继续地点提醒授权") }
                        }
                        "health" -> {
                            Text("仅在 Being 应用打开时读取已有步数、睡眠、运动、心率与体重记录；不写入健康数据。结果将用于 Being 回答，不作医疗诊断。", style = MaterialTheme.typography.bodySmall)
                            TextButton(onClick = { authorize(key, false) }) { Text(if (system.healthAvailable) "选择健康数据授权" else "安装或更新 Health Connect") }
                            TextButton(onClick = { context.startActivity(Intent(context, AndroidPortalHealthPrivacyActivity::class.java)) }) { Text("健康数据使用说明") }
                        }
                    }
                    HorizontalDivider()
                }
            }
            TextButton(onClick = { revision++ }) { Text("刷新授权与记录") }
            TextButton(onClick = { settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true) }) { Text("打开系统应用权限设置") }
            Text("待处理操作", style = MaterialTheme.typography.titleSmall)
            val pending = rows["actions"].orEmpty().filter { it.optString("status") == "pending_user_action" }
            if (pending.isEmpty()) Text("暂无待处理操作", style = MaterialTheme.typography.bodySmall)
            pending.forEach { row -> Row {
                TextButton(onClick = { context.startActivity(Intent(context, AndroidPortalActionActivity::class.java).putExtra("action_id", row.getString("id"))) }) { Text("处理 ${row.optString("kind")} · ${row.optJSONObject("arguments")?.optString("title").orEmpty()}") }
                TextButton(onClick = { perform { AndroidPortalActions(context, owner).cancel(row.getString("id")) } }) { Text("取消") }
            } }
            Text("我的提醒与地点提醒", style = MaterialTheme.typography.titleSmall)
            rows["reminders"].orEmpty().forEach { row ->
                Text("${row.optString("title")} · ${row.optString("at")} · ${row.optString("status")}", style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = { perform { AndroidPortalReminders(context, owner).call("delete", JSONObject().put("id", row.getString("id"))) } }) { Text("删除提醒") }
            }
            rows["geofences"].orEmpty().forEach { row ->
                Text("${row.optString("title")} · ${row.optString("transition")} · ${row.optString("status")}", style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = { perform { AndroidPortalLocation(context, owner).geofence("delete", JSONObject().put("id", row.getString("id"))) } }) { Text("删除地点提醒") }
            }
            Text("分享收件箱", style = MaterialTheme.typography.titleSmall)
            Text("在其他应用中选择「分享给 Being」。附件进入专用工作区，删除收件记录不会删除附件。", style = MaterialTheme.typography.bodySmall)
            rows["shares"].orEmpty().takeLast(20).reversed().forEach { row -> Row {
                TextButton(onClick = { selectedShare = row }, modifier = Modifier.weight(1f)) { Text(row.optString("text").take(50).ifBlank { "分享附件" }) }
                TextButton(onClick = { perform { AndroidPortalStore(context, owner).remove("shares", row.getString("id")) } }) { Text("删除") }
            } }
            Text("最近执行记录", style = MaterialTheme.typography.titleSmall)
            rows["activity"].orEmpty().takeLast(8).reversed().forEach { Text("${it.optString("time")} · ${it.optString("tool")} · ${it.optString("status")}", style = MaterialTheme.typography.bodySmall) }
        }
        message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
    } }
    selectedShare?.let { row -> AlertDialog(onDismissRequest = { selectedShare = null }, title = { Text("分享内容") },
        text = { Text(row.optString("text").take(3000) + "\n" + row.optJSONArray("files")?.toString().orEmpty()) }, confirmButton = { TextButton(onClick = { selectedShare = null }) { Text("关闭") } }) }
}

@Composable
private fun PortalPermissionStatus(allowed: Boolean, access: PortalSystemAccess) {
    Text("Being：${if (allowed) "已允许" else "未允许"} · 系统：${access.detail}",
        style = MaterialTheme.typography.bodySmall,
        color = if (allowed && access.state !in listOf("granted", "not_required")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
}

class AndroidPortalHealthPrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.app.AlertDialog.Builder(this).setTitle("Being 健康数据说明")
            .setMessage("仅在你开启当前 Being 的健康读取能力并授予系统权限后，按请求读取步数、睡眠、运动、心率与体重。\n\n健康记录会通过当前 Being 的连接发送给你选择的服务，用于回答或总结；该服务和模型提供方可能处理、保存这些结果。应用不将原始健康查询结果写入本地操作日志，不写回 Health Connect。\n\n可以在系统 Health Connect 中随时撤销权限，并关闭 Portal 的健康能力。撤销权限不删除 Being 服务已经收到的数据，请在该服务中删除相应记录。数据仅用于你请求的功能，不用于广告，不提供医疗诊断。")
            .setPositiveButton("知道了") { _, _ -> finish() }.setOnCancelListener { finish() }.show()
    }
}
