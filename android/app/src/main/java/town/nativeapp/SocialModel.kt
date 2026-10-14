package town.nativeapp

import android.app.Application
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

fun JSONObject.field(vararg names: String): String = names.firstNotNullOfOrNull { key -> if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null } ?: ""
fun JSONObject.rows(key: String): List<JSONObject> = optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } } ?: emptyList()
data class TownIdentity(val token: String, val id: String, val name: String)
class SocialModel(app: Application) : AndroidViewModel(app) {
    private val vault = Vault(app, "town-identity")
    var identity by mutableStateOf(runCatching { JSONObject(vault.load() ?: "").let { TownIdentity(it.getString("token"), it.getString("id"), it.optString("name")) } }.getOrNull()); private set
    var status by mutableStateOf("尚未配对"); private set
    var revision by mutableIntStateOf(0); private set
    var unread by mutableStateOf<Map<String,Int>>(emptyMap()); private set
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).connectTimeout(20,TimeUnit.SECONDS).readTimeout(60,TimeUnit.SECONDS).build()
    private var liveJob: Job? = null
    private var liveCall: Call? = null
    private val seen = linkedSetOf<String>()
    suspend fun request(path: String, privateRoute: Boolean = true, body: JSONObject? = null): JSONObject {
        require(path.startsWith("/api"))
        val credential = identity
        check(!privateRoute || credential != null) { "请先配对小镇身份。" }
        return withContext(Dispatchers.IO) {
            val b = Request.Builder().url("https://beings.town$path").header("Accept", "application/json")
            if (privateRoute && credential != null) b.header("Authorization", "Bearer ${credential.token}")
            if (body != null) b.post(body.toString().toRequestBody("application/json".toMediaType()))
            client.newCall(b.build()).execute().use { r ->
                check(r.isSuccessful) { if(path=="/api/client/pair/confirm"){if(r.code==429)"配对尝试过于频繁，请稍后重试。" else "配对失败（HTTP ${r.code}），请核对 Town ID 或 Being 名与配对码。"} else "Town 请求失败（HTTP ${r.code}）。" }
                val text = r.body!!.string(); check(text.length <= 4 * 1024 * 1024) { "内容过大，请减少读取数量。" }
                currentCoroutineContext().ensureActive()
                check(!privateRoute || identity == credential) { "身份已变化，请刷新。" }
                if (text.trimStart().startsWith("[")) JSONObject().put("members", JSONArray(text)) else JSONObject(text)
            }
        }
    }
    suspend fun pair(rawId: String, rawCode: String) {
        val trimmed = rawId.trim(); val id = if (trimmed.startsWith("t_")) trimmed else trimmed.lowercase(); val code = rawCode.trim().uppercase()
        require(Regex("^(t_[A-Za-z0-9_-]{1,62}|[a-z0-9_-]{1,64})$").matches(id) && Regex("^[A-Z0-9]{6}$").matches(code)) { "请输入有效的 Being 名和配对码。" }
        val result = request("/api/client/pair/confirm", false, JSONObject().put(if (id.startsWith("t_")) "town_id" else "being_id", id).put("code", code))
        val token = result.optString("token"); val returned = result.field("town_id", "being_id")
        check(result.optBoolean("ok") && Regex("^[A-Za-z0-9._~-]{16,2048}$").matches(token)) { "配对未确认。" }
        TownContracts.validatePair(id, result.optString("town_id").takeIf{it.isNotEmpty()}, result.optString("being_id").takeIf{it.isNotEmpty()}, token)
        currentCoroutineContext().ensureActive()
        val value = TownIdentity(token, returned.ifEmpty { id }, result.field("display_name", "speaker_name", "display"))
        vault.save(JSONObject().put("token", value.token).put("id", value.id).put("name", value.name).toString()); identity = value; unread = emptyMap(); seen.clear(); revision++; startLive()
    }
    fun unpair() { stopLive(); vault.save(null); identity = null; unread = emptyMap(); seen.clear(); status = "尚未配对"; revision++ }
    fun acknowledge(kind: String) { unread = unread + (kind to 0) }
    fun stopLive() { liveCall?.cancel(); liveJob?.cancel(); liveJob = null; liveCall = null }
    fun startLive() {
        stopLive(); val credential = identity ?: return
        liveJob = viewModelScope.launch {
            var attempts = 0
            while (isActive && credential == identity) {
                var fatal = false
                try {
                    status = "正在连接小镇…"
                    withContext(Dispatchers.IO) {
                        val url = HttpUrl.Builder().scheme("https").host("beings.town").addPathSegments("api/client/stream").addQueryParameter("token", credential.token).build()
                        val call = client.newCall(Request.Builder().url(url).header("Accept", "text/event-stream").build()); liveCall = call
                        call.execute().use { r ->
                            if (r.code in listOf(401,403)) { withContext(Dispatchers.Main) { status = "配对失效，请重新配对" }; fatal = true; return@withContext }
                            check(r.isSuccessful)
                            val source = r.body!!.source(); val parser = SSEParser(); var hello = false
                            while (true) {
                                currentCoroutineContext().ensureActive()
                                val line = source.readUtf8Line() ?: break; val event = parser.line(line) ?: continue; val data = JSONObject(event.data)
                                if (event.name == "hello") {
                                    val id = data.field("town_id","being_id")
                                    if (data.optBoolean("anonymous",true) || data.optString("token_kind") != "client" || !(id == credential.id || !credential.id.startsWith("t_") && data.optString("being_id") == credential.id)) { fatal = true; withContext(Dispatchers.Main) { status = "身份校验失败，请重新配对" }; return@withContext }
                                    hello = true; attempts = 0; withContext(Dispatchers.Main) { status = "小镇已连接"; revision++ }; continue
                                }
                                check(hello)
                                val channel = mapOf("dm" to "mail", "bonfire" to "bonfire", "fireside" to "firesides")[event.name] ?: continue
                                val key = "${event.name}:${data.field("fireside_id")}:${data.field("id","seq")}"
                                withContext(Dispatchers.Main) {
                                    if (identity == credential && seen.add(key)) {
                                        if (seen.size > 5000) { seen.clear(); seen.add(key) }
                                        if (data.field("sender_town_id","town_id","being_id") != credential.id) unread = unread + (channel to ((unread[channel] ?: 0) + 1))
                                        revision++
                                    }
                                }
                            }
                        }
                    }
                    if (fatal) return@launch
                    error("stream ended")
                } catch (e: CancellationException) { throw e }
                catch (_: Exception) { if (!isActive) return@launch; status = "连接中断，正在重连…"; attempts++; delay((attempts * 2000L).coerceAtMost(30000)) }
            }
        }
    }
    override fun onCleared() { stopLive(); super.onCleared() }
}
