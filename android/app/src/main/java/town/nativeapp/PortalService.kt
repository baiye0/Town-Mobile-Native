package town.nativeapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

/** One user-controlled foreground service, one supervised Rust child. */
class PortalService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var runner: Job? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Portal 运行状态", NotificationManager.IMPORTANCE_LOW))
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(ID, notification("正在启动"), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(ID, notification("正在启动"))
        } catch (_: Exception) {
            getSharedPreferences("portal", 0).edit().putBoolean("enabled", false).commit()
            PortalRuntime.update(PortalSnapshot("error", "系统未允许前台运行，请检查应用后台限制后重试。"))
            stopSelf()
            return START_NOT_STICKY
        }
        // Even a queued start cancelled by the user must satisfy Android's foreground deadline.
        if (intent?.action == STOP || !getSharedPreferences("portal", 0).getBoolean("enabled", false)) {
            PortalRuntime.stop(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (runner?.isActive != true) {
            wakeLock = getSystemService(android.os.PowerManager::class.java)
                .newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "$packageName:portal").apply { setReferenceCounted(false) }
            runner = scope.launch { supervise(startId) }.also { job ->
                job.invokeOnCompletion {
                    wakeLock?.let { if (it.isHeld) it.release() }
                    if (PortalRuntime.state.value.phase == "stopping") PortalRuntime.update(PortalSnapshot())
                }
            }
        }
        return START_STICKY
    }

    private fun publish(phase: String, detail: String, pid: Long? = null) {
        val next = PortalSnapshot(phase, detail, pid)
        if (PortalRuntime.state.value != next) {
            PortalRuntime.update(next)
            getSystemService(NotificationManager::class.java).notify(ID, notification(detail))
        }
    }

    private suspend fun supervise(startId: Int) {
        var failed = false
        var bridge: AndroidPortalBridge? = null
        try {
            val link = Vault(this).load()?.let { Connection.parse(it) } ?: error("No connection")
            val owner = digest(link.endpoint)
            val nativeBridge = AndroidPortalBridge(this, owner)
            bridge = nativeBridge
            val options = PortalRuntime.options(this).validated()
            val home = PortalRuntime.home(this).apply { mkdirs() }
            val workspace = PortalRuntime.workspace(this, owner).root.apply { mkdirs() }
            val config = File(home, "portal.toml").apply { writeText(options.toml(workspace)) }
            val ca = PortalRuntime.writeTrustStore(home)
            var crashes = 0
            while (currentCoroutineContext().isActive) {
                val nonce = UUID.randomUUID().toString()
                val stateFile = File(home, ".portal-connection-status.json")
                stateFile.delete()
                publish("starting", "正在启动")
                val builder = ProcessBuilder(PortalRuntime.executable(this).absolutePath, "--config", config.absolutePath)
                    .directory(workspace).redirectErrorStream(true)
                builder.environment().apply {
                    put("HOME", home.absolutePath)
                    put("HEART_ANDROID_PORT", nativeBridge.port.toString())
                    put("HEART_ANDROID_TOKEN", nativeBridge.token)
                    put("TMPDIR", File(home, "tmp").apply { mkdirs() }.absolutePath)
                    put("PATH", "/system/bin:/system/xbin")
                    put("PORTAL_CONNECT_LINK", "${link.endpoint}/?token=${link.token}")
                    put("HEART_PORTAL_PARENT_PID", android.os.Process.myPid().toString())
                    put("HEART_PORTAL_SUPERVISED", "1")
                    put("HEART_PORTAL_READY_FILE", File(home, "ready.json").absolutePath)
                    put("HEART_PORTAL_READY_NONCE", nonce)
                    put("PORTAL_MCP_TOKEN", UUID.randomUUID().toString())
                    put("SSL_CERT_FILE", ca.absolutePath)
                    put("RUST_LOG", "warn")
                    put("NO_COLOR", "1")
                }
                val child = builder.start()
                val launched = android.os.SystemClock.elapsedRealtime()
                // Always drain output, but never persist tool output, URLs or credentials to logcat/disk.
                val drain = scope.launch { runCatching { child.inputStream.use { input -> val buffer = ByteArray(4096); while (input.read(buffer) >= 0) { } } } }
                try {
                    while (child.isAlive) {
                        // Bounded leases renewed only while the supervised child is alive.
                        if (wakeLock?.isHeld == false) wakeLock?.acquire(10 * 60 * 1000L)
                        val sample = runCatching { if (stateFile.length() in 1..4096) stateFile.readText() else "" }.getOrDefault("")
                        val phase = PortalStateRules.connection(sample, nonce)
                        if (phase != null) publish(phase, when (phase) {
                            "connected" -> "已连接 ${link.being}"
                            "connecting" -> "正在连接 ${link.being}"
                            "retrying" -> "连接失败或中断，正在重试；请检查网络和 Being 连接"
                            else -> "连接配置无效，请重新连接 Being"
                        }, runCatching { JSONObject(sample).getLong("pid") }.getOrNull())
                        delay(500)
                    }
                    val lifetime = android.os.SystemClock.elapsedRealtime() - launched
                    if (child.exitValue() != 0 && lifetime < 60_000) crashes++ else crashes = 0
                    check(crashes < 3) { "Runtime repeatedly exited" }
                    publish("retrying", "运行时已退出，正在重新启动")
                } finally {
                    withContext(NonCancellable) {
                        child.destroy()
                        if (!child.waitFor(12, TimeUnit.SECONDS)) { child.destroyForcibly(); child.waitFor(2, TimeUnit.SECONDS) }
                        child.inputStream.close()
                        drain.cancelAndJoin()
                    }
                }
                delay(5000)
            }
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) {
            failed = true
            getSharedPreferences("portal", 0).edit().putBoolean("enabled", false).commit()
        } finally {
            bridge?.close()
            withContext(NonCancellable + Dispatchers.Main) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
                PortalRuntime.update(if (failed) PortalSnapshot("error", "Portal 启动失败。请检查连接、设备空间与运行时支持后重试。") else PortalSnapshot())
            }
        }
    }

    private fun notification(detail: String): Notification {
        val open = PendingIntent.getActivity(this, 220, Intent(this, MainActivity::class.java).putExtra("open_portal", true), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 221, Intent(this, PortalService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Being Portal").setContentText(detail).setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true).addAction(Notification.Action.Builder(null, "停止", stop).build()).build()
    }

    override fun onDestroy() {
        scope.cancel()
        if (runner == null && PortalRuntime.state.value.active) PortalRuntime.update(PortalSnapshot())
        super.onDestroy()
    }
    companion object { private const val CHANNEL = "portal-runtime"; private const val ID = 220; internal const val STOP = "town.nativeapp.STOP_PORTAL" }
}
