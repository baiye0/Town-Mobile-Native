package town.nativeapp

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

data class Connection(val endpoint: String, val being: String, val token: String, val secret: String) {
    fun url(path: String): HttpUrl = (endpoint + path).toHttpUrlOrNull()!!.newBuilder().addQueryParameter("token", token).build()
    companion object {
        fun parse(input: String): Connection {
            val u = input.trim().toHttpUrlOrNull() ?: error("请输入完整的 Being 链接。")
            require(u.isHttps && u.username.isEmpty() && u.password.isEmpty() && Regex("^/[a-zA-Z0-9_-]+/?$").matches(u.encodedPath)) { "请输入有效的 HTTPS Being 链接。" }
            val token = u.queryParameter("token") ?: ""
            require(Regex("^[a-zA-Z0-9._~-]{1,2048}$").matches(token)) { "链接缺少有效 token。" }
            val secret = u.queryParameter("relay_secret") ?: u.queryParameter("secret") ?: token
            require(!secret.contains('\n') && !secret.contains('\r')) { "无效的 secret。" }
            val being = u.encodedPath.trim('/')
            return Connection(u.newBuilder().encodedPath("/$being").query(null).fragment(null).build().toString(), being, token, secret)
        }
    }
}
data class SSEEvent(val name: String, val data: String)
class SSEParser {
    private var name = "message"
    private val data = mutableListOf<String>()
    fun line(raw: String): SSEEvent? {
        val line = raw.removeSuffix("\r")
        if (line.isEmpty()) { val result = if (data.isEmpty()) null else SSEEvent(name, data.joinToString("\n")); name = "message"; data.clear(); return result }
        if (line.startsWith(":")) return null
        val key = line.substringBefore(':'); val value = line.substringAfter(':', "").removePrefix(" ")
        when (key) { "event" -> name = value; "data" -> data.add(value) }
        return null
    }
}
