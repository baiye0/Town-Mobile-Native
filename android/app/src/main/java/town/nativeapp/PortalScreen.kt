package town.nativeapp

import android.Manifest
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun PortalScreen(connection: Connection?, onConnect: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by PortalRuntime.state.collectAsStateWithLifecycle()
    val saved = remember { PortalRuntime.options(context) }
    var name by rememberSaveable { mutableStateOf(saved.name) }
    var files by rememberSaveable { mutableStateOf(saved.files) }
    var web by rememberSaveable { mutableStateOf(saved.web) }
    var exec by rememberSaveable { mutableStateOf(saved.exec) }
    LaunchedEffect(state.active) {
        if (state.active) {
            val running = PortalRuntime.options(context)
            name = running.name; files = running.files; web = running.web; exec = running.exec
        }
    }
    var error by remember { mutableStateOf<String?>(null) }
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val supported = remember { PortalRuntime.executable(context).canExecute() }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { SettingsCard { Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsHeading("本机 Portal", Icons.Outlined.Computer, "让 Being 使用手机上的专用工作区")
            Text(state.detail, color = if (state.phase == "error") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
            Text("Heart Portal 0.9.2", style = MaterialTheme.typography.bodySmall)
            if (connection == null) TextButton(onClick = onConnect) { Text("先连接 Being") }
            else Text("当前 Being：${connection.being}", style = MaterialTheme.typography.bodySmall)
            if (!supported) Text("此设备缺少兼容的 Portal 运行时。", color = MaterialTheme.colorScheme.error)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(enabled = connection != null && supported && !state.active, onClick = {
                    error = null
                    scope.launch {
                        runCatching { PortalRuntime.start(context, PortalOptions(name.trim(), files, web, exec)) }
                            .onFailure { error = it.message }
                        if (PortalRuntime.state.value.active && Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                }) { Text("启动 Portal") }
                OutlinedButton(enabled = state.active && state.phase != "stopping", onClick = { PortalRuntime.stop(context) }) { Text("停止") }
            }
            Text("运行时会显示常驻通知；离开页面后仍可工作。网络恢复后自动重连。系统强行停止应用或重启手机后，请手动启动。", style = MaterialTheme.typography.bodySmall)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } } }
        item { SettingsCard { Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsHeading("能力设置", Icons.Outlined.Tune)
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("设备名称") }, singleLine = true, enabled = !state.active)
            SettingsToggle("工作区文件与搜索", files, !state.active) { files = it }
            SettingsToggle("网页获取", web, !state.active) { web = it }
            SettingsToggle("Shell 命令执行", exec, !state.active) { exec = it }
            Text("Shell 以应用身份运行，可访问应用私有数据和凭据，文件工作区边界不限制 Shell；仅向信任的 Being 开放。", style = MaterialTheme.typography.bodySmall)
            Text("截图、桌面 Kit、自定义 MCP 和子代理未启用；此运行时不包含 Node/Python，也不控制其他应用。更改能力后需重新启动。", style = MaterialTheme.typography.bodySmall)
        } } }
        item { AndroidPortalSettings() }
        item { PortalWorkspacePanel() }
        item { PortalBackgroundGuidance() }
    }
}

@Composable
private fun PortalBackgroundGuidance() {
    val context = LocalContext.current
    var exempt by remember { mutableStateOf(false) }
    var notifications by remember { mutableStateOf(true) }
    androidx.lifecycle.compose.LifecycleResumeEffect(Unit) {
        exempt = context.getSystemService(android.os.PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
        notifications = context.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()
        onPauseOrDispose { }
    }
    SettingsCard { Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SettingsHeading("后台运行", Icons.Outlined.BatteryFull)
        Text(if (exempt) "已允许忽略电池优化" else "省电策略可能暂停 Portal。需要长时间保持连接时，可在系统设置中允许后台运行。", style = MaterialTheme.typography.bodySmall)
        Text("Portal 运行期间保持 CPU 唤醒，会增加耗电；不用时请停止。小米 / Redmi 可检查「省电策略：无限制」和后台自启动，其他手机请检查应用电池设置。", style = MaterialTheme.typography.bodySmall)
        if (!notifications) Text("通知已关闭；请在应用设置中开启，以便查看状态和停止 Portal。", style = MaterialTheme.typography.bodySmall)
        Row {
            TextButton(onClick = { runCatching { context.startActivity(android.content.Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } }) { Text("电池优化设置") }
            TextButton(onClick = { context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))) }) { Text("应用设置") }
        }
    } }
}

@Composable
private fun PortalWorkspacePanel() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val workspace = remember { PortalRuntime.workspace(context) }
    var directory by rememberSaveable { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<File>>(emptyList()) }
    var revision by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf<String?>(null) }
    var exportPath by rememberSaveable { mutableStateOf<String?>(null) }
    fun perform(action: suspend () -> Unit) {
        busy = true; info = null
        scope.launch {
            try { withContext(Dispatchers.IO) { action() }; revision++ }
            catch (_: Exception) { info = "文件操作未完成：请检查文件是否存在、是否重名，以及大小是否超过 10 MB。" }
            finally { busy = false }
        }
    }
    val import = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) perform {
            val filename = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: "import-${System.currentTimeMillis()}"
            context.contentResolver.openInputStream(uri)?.use { workspace.importFile(filename, it) } ?: error("Cannot read file")
        }
    }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val relative = exportPath
        exportPath = null
        if (uri != null && relative != null) perform {
            val source = workspace.resolve(relative)
            check(source.isFile && source.length() <= PortalWorkspace.MAX_BYTES)
            context.contentResolver.openOutputStream(uri)?.use { output -> source.inputStream().use { it.copyTo(output) } } ?: error("Cannot export")
        }
    }
    LaunchedEffect(directory, revision) {
        entries = withContext(Dispatchers.IO) { runCatching { workspace.list(directory) }.getOrDefault(emptyList()) }
    }
    SettingsCard { Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SettingsHeading("工作区", Icons.Outlined.Folder, if (directory.isEmpty()) "专用目录 · 最多显示 500 项" else directory)
        Text("导入的文件可被 Being 读取和修改。卸载应用会删除工作区，请先导出需要保留的文件。", style = MaterialTheme.typography.bodySmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(enabled = !busy, onClick = { import.launch(arrayOf("*/*")) }) { Text("导入到根目录") }
            TextButton(enabled = !busy, onClick = { revision++ }) { Text("刷新") }
            if (directory.isNotEmpty()) TextButton(onClick = { directory = File(directory).parent ?: "" }) { Text("上一级") }
        }
        if (entries.isEmpty()) Text("目录为空", style = MaterialTheme.typography.bodySmall)
        entries.forEach { file ->
            val relative = file.relativeTo(workspace.root.canonicalFile).path
            TextButton(enabled = !busy, onClick = {
                if (file.isDirectory) directory = relative
                else { exportPath = relative; export.launch(file.name) }
            }) { Text(if (file.isDirectory) "文件夹 · ${file.name}" else "导出 · ${file.name}（${file.length()} B）") }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        info?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    } }
}
