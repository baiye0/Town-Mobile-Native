package town.nativeapp

import android.content.Context
import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.security.KeyStore
import java.util.UUID
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

data class PortalSnapshot(val phase: String = "stopped", val detail: String = "尚未启动", val pid: Long? = null) {
    val active get() = phase in setOf("starting", "connecting", "connected", "retrying", "invalid", "stopping")
}

object PortalRuntime {
    private val mutable = MutableStateFlow(PortalSnapshot())
    val state = mutable.asStateFlow()
    internal fun update(value: PortalSnapshot) { mutable.value = value }
    fun home(context: Context) = File(context.noBackupFilesDir, "portal")
    fun workspace(context: Context, owner: String = AndroidPortalPolicy.owner(context)): PortalWorkspace {
        require(owner.isEmpty() || owner.matches(Regex("[0-9a-f]{64}")))
        return PortalWorkspace(File(home(context), "workspaces/${owner.ifEmpty { "unconnected" }}"))
    }
    fun executable(context: Context) = File(context.applicationInfo.nativeLibraryDir, "libheart_portal.so")

    fun options(context: Context): PortalOptions {
        val prefs = context.getSharedPreferences("portal", 0)
        val name = prefs.getString("name", null) ?: "android-${UUID.randomUUID().toString().take(8)}".also {
            prefs.edit().putString("name", it).apply()
        }
        return PortalOptions(name, prefs.getBoolean("files", true), prefs.getBoolean("web", true), prefs.getBoolean("exec", false))
    }

    fun start(context: Context, options: PortalOptions) {
        options.validated()
        check(executable(context).canExecute()) { "此安装包不支持当前设备的 Portal 运行时。" }
        check(Vault(context).load()?.let { runCatching { Connection.parse(it) }.isSuccess } == true) { "请先连接 Being。" }
        check(!state.value.active) { "Portal 正在运行，请先停止。" }
        context.getSharedPreferences("portal", 0).edit().putString("name", options.name)
            .putBoolean("files", options.files).putBoolean("web", options.web).putBoolean("exec", options.exec)
            .putBoolean("enabled", true).commit()
        update(PortalSnapshot("starting", "正在启动"))
        try { context.startForegroundService(Intent(context, PortalService::class.java)) }
        catch (e: Exception) {
            context.getSharedPreferences("portal", 0).edit().putBoolean("enabled", false).commit()
            update(PortalSnapshot("error", "系统未允许启动 Portal，请回到应用后重试。"))
            throw IllegalStateException(state.value.detail, e)
        }
    }

    fun stop(context: Context) {
        context.getSharedPreferences("portal", 0).edit().putBoolean("enabled", false).commit()
        val pendingStart = state.value.phase == "starting"
        if (state.value.active) update(PortalSnapshot("stopping", "正在停止"))
        // Do not remove a queued startForegroundService before onStartCommand can
        // fulfill its foreground obligation. Queue STOP behind that start instead.
        if (pendingStart) {
            try { context.startService(Intent(context, PortalService::class.java).setAction(PortalService.STOP)); return }
            catch (_: Exception) { /* Fall back when Android has already removed the service. */ }
        }
        val stopped = context.stopService(Intent(context, PortalService::class.java))
        if (!stopped && state.value.phase == "stopping") update(PortalSnapshot())
    }

    /** Export the Android system trust store for rustls; never install an accept-all verifier. */
    internal fun writeTrustStore(home: File): File {
        val trust = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(null as KeyStore?) }
        val certificates = trust.trustManagers.filterIsInstance<X509TrustManager>().flatMap { it.acceptedIssuers.toList() }
        check(certificates.isNotEmpty()) { "System trust store is empty" }
        return File(home, "ca.pem").apply {
            bufferedWriter().use { output -> certificates.forEach { certificate ->
                output.appendLine("-----BEGIN CERTIFICATE-----")
                output.appendLine(java.util.Base64.getMimeEncoder(64, byteArrayOf(10)).encodeToString(certificate.encoded))
                output.appendLine("-----END CERTIFICATE-----")
            } }
        }
    }
}
