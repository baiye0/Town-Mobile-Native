package town.nativeapp

import android.Manifest
import android.app.Activity
import android.app.Instrumentation
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import org.json.JSONObject

/** Emulator-only UI permission workflow. Never alters a phone's account or permission settings. */
class PortalPermissionInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    private fun shell(command: String): String = uiAutomation.executeShellCommand(command).use {
        android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().use { reader -> reader.readText() }
    }
    private fun nodes(): List<AccessibilityNodeInfo> {
        val result = mutableListOf<AccessibilityNodeInfo>()
        fun visit(node: AccessibilityNodeInfo?) {
            if (node == null) return
            result += node
            for (i in 0 until node.childCount) visit(node.getChild(i))
        }
        visit(uiAutomation.rootInActiveWindow)
        return result
    }
    private fun await(label: String, condition: () -> Boolean) {
        repeat(100) { if (condition()) return; Thread.sleep(100) }
        error("Timed out: $label; UI=${nodes().mapNotNull { it.text }.joinToString(" | ")}")
    }
    private fun click(label: String, predicate: (AccessibilityNodeInfo) -> Boolean) {
        var found: AccessibilityNodeInfo? = null
        await(label) { nodes().firstOrNull(predicate).also { found = it } != null }
        var node = found!!
        while (!node.isClickable && node.parent != null) node = node.parent
        check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) { "Cannot click $label" }
    }
    override fun onStart() {
        var host: ScrollHarnessActivity? = null
        var previous: String? = null
        var prepared = false
        val passed = mutableListOf<String>()
        var code = Activity.RESULT_CANCELED
        var report: String
        try {
            check(Build.MODEL.startsWith("sdk_gphone") && Build.HARDWARE == "ranchu") { "Emulator only" }
            previous = Vault(targetContext).load()
            check(previous == null) { "Use a disposable emulator app without a connected Being" }
            check(Manifest.permission.READ_CALENDAR !in AndroidPortalPermissions.snapshot(targetContext).granted) { "Start with calendar denied" }
            Vault(targetContext).save("https://127.0.0.1:1/permission-fixture/?token=synthetic")
            prepared = true
            val owner = AndroidPortalPolicy.owner(targetContext)
            val monitor = addMonitor(ScrollHarnessActivity::class.java.name, null, false)
            shell("am start -n ${targetContext.packageName}/${ScrollHarnessActivity::class.java.name}")
            host = waitForMonitorWithTimeout(monitor, 10000) as? ScrollHarnessActivity ?: error("Missing harness")
            runOnMainSync {
                host.setContent { MaterialTheme { Column(Modifier.verticalScroll(rememberScrollState())) { AndroidPortalSettings() } } }
            }
            click("expand") { it.text?.toString() == "展开授权设置" }
            await("initial missing OS grant") { nodes().any { it.text?.contains("Being：未允许 · 系统：待系统授权") == true } }
            passed += "Initial UI reports OS permission missing, independently of policy"
            click("calendar read toggle") { it.text?.toString() == "允许 Being 读取" }
            click("real OS deny button") { it.viewIdResourceName?.endsWith("/permission_deny_button") == true }
            await("denied UI") { nodes().any { it.text?.contains("Being：已允许 · 系统：待系统授权") == true } }
            check(AndroidPortalPolicy.enabled(targetContext, owner, "calendar"))
            check(Manifest.permission.READ_CALENDAR !in AndroidPortalPermissions.snapshot(targetContext).granted)
            val tool = AndroidPortalTools(targetContext, owner)
            check(runCatching { tool.call("portal_android_calendar", JSONObject().put("action", "calendars")) }.isFailure)
            passed += "Toggle opens real OS prompt; denial stays visibly pending and tool cannot read"
            click("retry") { it.text?.toString() == "继续系统授权" }
            click("deny again") { it.viewIdResourceName?.contains("/permission_deny_") == true }
            await("return from denial") { nodes().any { it.text?.toString() == "继续系统授权" } }
            click("blocked retry opens settings") { it.text?.toString() == "继续系统授权" }
            await("system app settings") { uiAutomation.rootInActiveWindow?.packageName?.toString() == "com.android.settings" }
            passed += "Repeated denial opens system settings instead of pretending authorization succeeded"
            shell("pm grant ${targetContext.packageName} ${Manifest.permission.READ_CALENDAR}")
            uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            await("resume refresh") { nodes().any { it.text?.contains("Being：已允许 · 系统：已授权") == true } }
            check(Manifest.permission.READ_CALENDAR in AndroidPortalPermissions.snapshot(targetContext).granted)
            check(!AndroidPortalPolicy.enabled(targetContext, owner, "calendar", true))
            val capabilities = tool.call("portal_android_capabilities", JSONObject().put("action", "get"))
            val calendar = capabilities.getJSONArray("system_access").getJSONObject(0)
            check(calendar.getJSONObject("read").getString("state") == "granted")
            passed += "Returning from settings refreshes real permission; read authorization never enables Being writes"
            click("disable calendar") { it.text?.toString() == "允许 Being 读取" }
            await("disabled but OS retained") { nodes().any { it.text?.contains("Being：未允许 · 系统：已授权") == true } }
            check(runCatching { tool.call("portal_android_calendar", JSONObject().put("action", "calendars")) }.isFailure)
            passed += "Disabling Being access blocks calls while honestly showing retained system permission"
            report = "PASS ${passed.size}\n" + passed.joinToString("\n")
            code = Activity.RESULT_OK
        } catch (error: Throwable) { report = "FAIL after ${passed.size}\n${passed.joinToString("\n")}\n${error.stackTraceToString()}" }
        finally {
            host?.let { runOnMainSync { it.finish() } }
            if (prepared) Vault(targetContext).save(previous)
        }
        finish(code, Bundle().apply { putString("stream", report) })
    }
}
