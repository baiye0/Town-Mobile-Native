package town.nativeapp

import android.content.Context
import org.json.JSONObject
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore

/** Private loopback protocol: one bounded UTF-8 JSON request/response per socket. */
class AndroidPortalBridge(context: Context, owner: String) : AutoCloseable {
    val token = UUID.randomUUID().toString() + UUID.randomUUID().toString()
    private val server = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
    val port get() = server.localPort
    private val clients = java.util.concurrent.ConcurrentHashMap.newKeySet<Socket>()
    private val slots = Semaphore(4)
    private val workers = Executors.newFixedThreadPool(4)
    private val engine = AndroidPortalTools(context.applicationContext, owner)
    private val acceptor = Thread({
        while (!server.isClosed) {
            val socket = try { server.accept() } catch (_: Exception) { break }
            if (!slots.tryAcquire()) { socket.close(); continue }
            clients.add(socket)
            try { workers.execute {
                try { socket.use { client ->
                    // A per-read timeout alone lets a trickling peer keep a worker forever.
                    val deadline = System.nanoTime() + 2_000_000_000L
                    val input = client.getInputStream(); val bytes = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (bytes.size() <= 262144) {
                        val remaining = deadline - System.nanoTime()
                        check(remaining > 0) { "Request timed out" }
                        client.soTimeout = ((remaining + 999_999L) / 1_000_000L).toInt().coerceAtLeast(1)
                        val count = input.read(buffer, 0, minOf(buffer.size, 262145 - bytes.size()))
                        if (count < 0) break
                        val newline = (0 until count).firstOrNull { buffer[it] == 10.toByte() }
                        bytes.write(buffer, 0, newline ?: count)
                        if (newline != null) break
                    }
                    check(bytes.size() <= 262144) { "Request too large" }
                    val request = JSONObject(bytes.toString("UTF-8"))
                    check(MessageDigest.isEqual(token.toByteArray(), request.optString("token").toByteArray())) { "Unauthenticated" }
                    val response = try {
                        JSONObject().put("result", if (request.optString("method") == "list") engine.list()
                        else engine.call(request.getString("name"), request.optJSONObject("arguments") ?: JSONObject()))
                    } catch (e: Exception) { JSONObject().put("error", engine.safeError(e)) }
                    val encoded = response.toString().toByteArray()
                    check(encoded.size <= 1024 * 1024) { "Response too large" }
                    client.getOutputStream().write(encoded + byteArrayOf(10))
                } } catch (_: Exception) { /* Invalid requests never reach logs or tools. */ }
                finally { clients.remove(socket); slots.release() }
            } } catch (_: Exception) { socket.close(); clients.remove(socket); slots.release() }
        }
    }, "android-portal-bridge").apply { isDaemon = true; start() }
    override fun close() { server.close(); clients.forEach { runCatching { it.close() } }; workers.shutdownNow(); acceptor.interrupt() }
}
