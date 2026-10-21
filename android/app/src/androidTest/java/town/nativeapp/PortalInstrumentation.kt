package town.nativeapp

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONObject
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Real APK executable + real service + real WebSocket/MCP. Only the isolated QA app may run this. */
class PortalInstrumentation : Instrumentation() {
    private var publicNetwork = false
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); publicNetwork = arguments?.getString("network") == "true"; start() }
    private fun await(label: String, seconds: Int = 20, condition: () -> Boolean) {
        repeat(seconds * 10) { if (condition()) return; Thread.sleep(100) }
        error("Timed out: $label; ${PortalRuntime.state.value}")
    }

    override fun onStart() {
        val passed = mutableListOf<String>()
        val server = MockWebServer()
        var host: Activity? = null
        var resultCode = Activity.RESULT_CANCELED
        var report = ""
        try {
            check(targetContext.packageName.endsWith(".portalqa")) { "Build with -PportalQa=true; never replace user credentials" }
            val version = ProcessBuilder(PortalRuntime.executable(targetContext).absolutePath, "--version").redirectErrorStream(true).start()
            check(version.waitFor(10, TimeUnit.SECONDS) && version.exitValue() == 0) { "Standalone Android --version must work without APK host variables" }
            passed += "Shared Android runtime remains usable without embedded-host environment"
            val sessions = LinkedBlockingQueue<Relay>()
            val callbacks = LinkedBlockingQueue<String>()
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.method == "POST") callbacks.offer(request.body.readUtf8())
                    return when (request.path) {
                        "/_relay" -> MockResponse().withWebSocketUpgrade(Relay(sessions))
                        else -> MockResponse().setBody("{\"ok\":true}").addHeader("Content-Type", "application/json")
                    }
                }
            }
            server.start()
            val connection = "https://127.0.0.1:${server.port}/fixture/?token=synthetic-portal-token"
            Vault(targetContext).save(connection)
            val monitor = addMonitor(MainActivity::class.java.name, null, false)
            uiAutomation.executeShellCommand("am start -n ${targetContext.packageName}/${MainActivity::class.java.name} --ez open_portal true").use {
                android.os.ParcelFileDescriptor.AutoCloseInputStream(it).use { stream -> stream.readBytes() }
            }
            host = waitForMonitorWithTimeout(monitor, 10000) ?: error("QA activity did not start")
            val options = PortalOptions("android-fixture")
            runOnMainSync { PortalRuntime.start(targetContext, options) }
            var relay = sessions.poll(20, TimeUnit.SECONDS) ?: error("No relay handshake")
            await("connected") { PortalRuntime.state.value.phase == "connected" }
            check(relay.handshake.getString("being_id") == "fixture")
            check(relay.handshake.getString("portal_name") == options.name)
            check(relay.handshake.getString("loom_token") == "synthetic-portal-token")
            runOnMainSync { check(runCatching { PortalRuntime.start(targetContext, options) }.isFailure) }
            passed += "Packaged ELF starts in nativeLibraryDir; authenticated relay handshake and state"
            relay.request("initialize", JSONObject().put("protocolVersion", "2024-11-05").put("capabilities", JSONObject()).put("clientInfo", JSONObject().put("name", "fixture").put("version", "1")))
            val listed = relay.request("tools/list").getJSONObject("result").getJSONArray("tools")
            val names = (0 until listed.length()).map { listed.getJSONObject(it).getString("name") }
            check(listOf("portal_status", "portal_file_read", "portal_file_write", "portal_search", "portal_web_fetch").all { it in names })
            check(listOf("portal_exec", "portal_screenshot").none { it in names })
            check(names.none { it.startsWith("portal_subagent_") })
            val status = relay.tool("portal_status")
            check(!status.toString().contains("synthetic-portal-token"))
            passed += "MCP initialize/list/status; only configured capabilities; credentials absent"
            passed += AndroidNativePortalQa.run(this) { name, arguments -> relay.tool(name, arguments) }
            check(!relay.tool("portal_file_write", JSONObject().put("path", "中文.txt").put("content", "hello Android Portal 中文")).has("error"))
            check(relay.tool("portal_file_read", JSONObject().put("path", "中文.txt")).toString().contains("hello Android Portal 中文"))
            check(relay.tool("portal_file_list", JSONObject().put("path", ".")).toString().contains("中文.txt"))
            check(relay.tool("portal_search", JSONObject().put("pattern", "Android")).toString().contains("中文.txt"))
            val denied = relay.tool("portal_file_read", JSONObject().put("path", "../portal.toml"))
            check(denied.has("error") || denied.optJSONObject("result")?.optBoolean("isError") == true)
            val escape = java.io.File(PortalRuntime.workspace(targetContext).root, "escape")
            escape.delete()
            android.system.Os.symlink(java.io.File(PortalRuntime.home(targetContext), "portal.toml").absolutePath, escape.absolutePath)
            check(runCatching { PortalRuntime.workspace(targetContext).resolve("escape") }.isFailure)
            val symlinkDenied = relay.tool("portal_file_read", JSONObject().put("path", "escape"))
            check(symlinkDenied.has("error") || symlinkDenied.optJSONObject("result")?.optBoolean("isError") == true)
            escape.delete()
            val execDenied = relay.tool("portal_exec", JSONObject().put("command", "echo must-not-run"))
            check(execDenied.has("error") || execDenied.optJSONObject("result")?.optBoolean("isError") == true)
            val localFetch = relay.tool("portal_web_fetch", JSONObject().put("url", "http://127.0.0.1:${server.port}/fixture-page"))
            check(localFetch.has("error") || localFetch.optJSONObject("result")?.optBoolean("isError") == true)
            passed += "Real workspace Unicode write/read/list/search and traversal denial"
            if (publicNetwork) {
                val fetched = relay.tool("portal_web_fetch", JSONObject().put("url", "https://example.com").put("max_chars", 10000))
                check(fetched.toString().contains("Example Domain")) { "Public HTTPS web fetch failed: $fetched" }
                passed += "Android DNS and HTTPS web fetch without curl"
            }
            relay.socket.close(1000, "fixture disconnect")
            relay = sessions.poll(35, TimeUnit.SECONDS) ?: error("No reconnect")
            await("reconnected") { PortalRuntime.state.value.phase == "connected" }
            relay.request("tools/list")
            passed += "WebSocket loss reconnects and serves MCP again"
            val firstPid = PortalRuntime.state.value.pid!!
            runOnMainSync { PortalRuntime.stop(targetContext) }
            await("stopped") { PortalRuntime.state.value.phase == "stopped" }
            check(!java.io.File("/proc/$firstPid").exists())
            Thread.sleep(5500)
            check(sessions.isEmpty())
            passed += "Explicit stop reaps native process and suppresses restart"
            runOnMainSync { PortalRuntime.start(targetContext, options.copy(exec = true)) }
            relay = sessions.poll(20, TimeUnit.SECONDS) ?: error("No second start")
            await("second connected") { PortalRuntime.state.value.phase == "connected" }
            check(relay.tool("portal_exec", JSONObject().put("command", "printf portal-shell-ok")).toString().contains("portal-shell-ok"))
            val background = relay.tool("portal_exec", JSONObject().put("command", "printf background-ok").put("background", true))
            val backgroundId = JSONObject(background.getJSONObject("result").getJSONArray("content").getJSONObject(0).getString("text")).getString("session_id")
            Thread.sleep(500)
            check(relay.tool("portal_process", JSONObject().put("action", "poll").put("session_id", backgroundId)).toString().contains("background-ok"))
            check(callbacks.poll(15, TimeUnit.SECONDS)?.contains("background-ok") == true)
            val timeout = relay.tool("portal_exec", JSONObject().put("command", "echo $$ > timeout-pid; exec sleep 60").put("timeout_secs", 1))
            check(timeout.has("error") || timeout.optJSONObject("result")?.optBoolean("isError") == true)
            val timedOutPid = PortalRuntime.workspace(targetContext).resolve("timeout-pid").readText().trim()
            await("timed-out shell reaped") { !java.io.File("/proc/$timedOutPid").exists() }
            passed += "Background process output; timed-out shell is killed"
            val pid = PortalRuntime.state.value.pid!!
            android.os.Process.sendSignal(pid.toInt(), 9)
            relay = sessions.poll(25, TimeUnit.SECONDS) ?: error("No crash recovery")
            await("new pid") { PortalRuntime.state.value.phase == "connected" && PortalRuntime.state.value.pid != pid }
            passed += "Opt-in Android shell execution and crash recovery"
            val beforeRestart = PortalRuntime.state.value.pid
            relay.tool("portal_restart")
            relay = sessions.poll(25, TimeUnit.SECONDS) ?: error("No controlled restart")
            await("controlled restart connected") { PortalRuntime.state.value.phase == "connected" && PortalRuntime.state.value.pid != beforeRestart }
            check(relay.tool("portal_file_read", JSONObject().put("path", "中文.txt")).toString().contains("hello Android Portal"))
            passed += "portal_restart restarts runtime; workspace persists"
            runOnMainSync { PortalRuntime.stop(targetContext) }
            await("stop for capability change") { PortalRuntime.state.value.phase == "stopped" }
            runOnMainSync { PortalRuntime.start(targetContext, options.copy(files = false, web = false)) }
            relay = sessions.poll(20, TimeUnit.SECONDS) ?: error("No restricted start")
            await("restricted connected") { PortalRuntime.state.value.phase == "connected" }
            for (tool in listOf("portal_file_read", "portal_file_write", "portal_file_edit", "portal_file_list", "portal_search", "portal_web_fetch", "portal_exec", "portal_oauth_authorize", "portal_tools_reload")) {
                val response = relay.tool(tool)
                check(response.toString().contains("disabled") || response.toString().contains("unavailable")) { "Disabled tool not explicitly rejected: $tool: $response" }
            }
            passed += "Disabled capabilities reject direct calls, including unsupported Android tools"
            // Render the actual settings screen after a connected run.
            runOnMainSync { (host as MainActivity).recreate() }
            Thread.sleep(1000)
            uiAutomation.takeScreenshot()?.let { bitmap ->
                java.io.File(targetContext.getExternalFilesDir(null), "portal-qa.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            }
            runOnMainSync { PortalRuntime.stop(targetContext) }
            await("stop before rapid toggle") { PortalRuntime.state.value.phase == "stopped" }
            runOnMainSync { PortalRuntime.start(targetContext, options); PortalRuntime.stop(targetContext) }
            await("rapid start/stop") { PortalRuntime.state.value.phase == "stopped" }
            Thread.sleep(6000) // Also cover Android's deferred foreground-start timeout.
            check(sessions.isEmpty())
            passed += "Immediate stop during service startup does not leave a stuck state or child"
            resultCode = Activity.RESULT_OK
            report = "PASS ${passed.size}\n" + passed.joinToString("\n")
        } catch (error: Throwable) {
            report = "FAIL after ${passed.size}: ${error.stackTraceToString()}\n" + passed.joinToString("\n")
        } finally {
            if (targetContext.packageName.endsWith(".portalqa")) {
                runOnMainSync { PortalRuntime.stop(targetContext); host?.finish() }
                runCatching { await("cleanup") { !PortalRuntime.state.value.active } }
                Vault(targetContext).save(null)
            }
            server.close()
        }
        finish(resultCode, Bundle().apply { putString("stream", report) })
    }

    private class Relay(private val sessions: LinkedBlockingQueue<Relay>) : WebSocketListener() {
        lateinit var socket: WebSocket
        lateinit var handshake: JSONObject
        private val replies = LinkedBlockingQueue<JSONObject>()
        private val ids = AtomicInteger()
        override fun onOpen(webSocket: WebSocket, response: Response) { socket = webSocket }
        override fun onMessage(webSocket: WebSocket, text: String) {
            for (line in text.trim().lines()) {
                val json = JSONObject(line)
                if (!::handshake.isInitialized) {
                    handshake = json
                    webSocket.send("{\"ok\":true,\"relay_keepalive\":\"text-v1\"}")
                    sessions.offer(this)
                } else if (json.optString("type") == "keepalive") webSocket.send("{\"type\":\"keepalive_ack\"}")
                else if (json.has("id")) replies.offer(json)
            }
        }
        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(code, reason) }
        fun request(method: String, params: JSONObject = JSONObject()): JSONObject {
            val id = ids.incrementAndGet()
            check(socket.send(JSONObject().put("jsonrpc", "2.0").put("id", id).put("method", method).put("params", params).toString()))
            val response = replies.poll(20, TimeUnit.SECONDS) ?: error("No response to $method")
            check(response.getInt("id") == id)
            return response
        }
        fun tool(name: String, args: JSONObject = JSONObject()) = request("tools/call", JSONObject().put("name", name).put("arguments", args))
    }
}
