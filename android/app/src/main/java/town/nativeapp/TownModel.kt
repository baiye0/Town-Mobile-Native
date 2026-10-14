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
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

data class Message(val role: String, val text: String, val sceneID:String?=null,val sequence:Int?=null,val kind:String?=null,val timestamp:String?=null,val sceneLabel:String?=null)
data class Room(val id: String = "mobile-${UUID.randomUUID()}", val endpoint: String, val title: String = "新对话", val messages: List<Message> = emptyList())
class TownModel(app: Application) : AndroidViewModel(app) {
    private val vault = Vault(app)
    var connection by mutableStateOf(vault.load()?.let { runCatching { Connection.parse(it) }.getOrNull() }); private set
    var rooms by mutableStateOf<List<Room>>(emptyList()); private set
    var selected by mutableStateOf<String?>(null)
    private var allScenes by mutableStateOf(app.getSharedPreferences("scenes",0).getBoolean("all.${connection?.endpoint}",false))
    var showAllScenes:Boolean
        get()=allScenes
        set(value){allScenes=value;connection?.let{scenePrefs.edit().putBoolean("all.${it.endpoint}",value).apply()}}
    var showSBS by mutableStateOf(false)
    private val scenePrefs=app.getSharedPreferences("scenes",0)
    private var directory by mutableStateOf(runCatching { JSONObject(scenePrefs.getString("directory","{}")!!) }.getOrDefault(JSONObject()))
    var timeline by mutableStateOf<List<Message>>(emptyList()); private set
    var historyLoading by mutableStateOf(false);private set
    private val historyFile=File(app.filesDir,"history-cache.json")
    private var historyCache=runCatching{JSONObject(historyFile.readText())}.getOrDefault(JSONObject())
    val mainID get()=connection?.let { scenePrefs.getString("main.${it.endpoint}",null) }
    private val displayState = derivedStateOf { (if(showAllScenes)HistoryRules.merge(rooms.filter{it.endpoint==connection?.endpoint}.flatMap{r->r.messages.map{it.copy(sceneID=it.sceneID ?: r.id)}},timeline) else if(showSBS)((current?.messages ?: emptyList())+timeline.filter{it.sceneID==null&&it.role!="user"}).sortedBy{it.sequence ?: Int.MAX_VALUE} else current?.messages ?: emptyList()).filter { it.text.isNotBlank() } }
    val displayMessages get() = displayState.value
    private fun sceneIDs():List<String>{val a=directory.optJSONArray(connection?.endpoint ?: "") ?: JSONArray();return (0 until a.length()).map{a.getString(it)}}
    private fun saveDirectory(ids:List<String>){val c=connection ?: return;val next=JSONObject(directory.toString());next.put(c.endpoint,JSONArray(ids));directory=next;scenePrefs.edit().putString("directory",next.toString()).apply()}
    private fun ensureMain(){
        val c=connection ?: return
        val id=mainID ?: "mobile-${UUID.randomUUID()}".also{scenePrefs.edit().putString("main.${c.endpoint}",it).apply()}
        if(rooms.none{it.id==id&&it.endpoint==c.endpoint})rooms=listOf(Room(id,c.endpoint,"主对话"))+rooms
        val ids=if(directory.has(c.endpoint))sceneIDs() else rooms.filter{it.endpoint==c.endpoint&&it.id.startsWith("mobile-")}.map{it.id}
        saveDirectory(listOf(id)+ids.filter{it!=id})
    }
    fun selectScene(id:String){if(busy||visibleRooms.none{it.id==id})return;sceneDrafts["${connection?.endpoint}|$selected"]=draft;selected=id;draft=sceneDrafts["${connection?.endpoint}|$id"] ?: "";showSBS=scenePrefs.getBoolean("sbs.${connection?.endpoint}|$id",false)}
    fun sceneName(message:Message)=message.sceneID?.let{id->rooms.find{it.id==id&&it.endpoint==connection?.endpoint}?.title ?: message.sceneLabel ?: id} ?: "未标记场景"
    fun saveSBS(){scenePrefs.edit().putBoolean("sbs.${connection?.endpoint}|$selected",showSBS).apply()}
    fun createScene(name:String,binding:String?=null){
        val c=connection ?: return;if(busy)return
        require(SceneRules.validName(name)){"场景名称需为 1–128 个字符。"}
        require(binding==null||SceneRules.validID(binding)){"场景 ID 需为 1–256 个非空白 ASCII 字符。"}
        check(visibleRooms.size<500){"当前 Being 的场景数量已达上限。"}
        val id=binding ?: "mobile-${UUID.randomUUID()}"
        if(id !in sceneIDs()){
            if(rooms.any{it.id==id&&it.endpoint==c.endpoint})rooms=rooms.map{if(it.id==id&&it.endpoint==c.endpoint)it.copy(title=name.trim()) else it}
            else rooms=rooms+Room(id,c.endpoint,name.trim())
            saveDirectory(sceneIDs()+id)
        }
        selectScene(id);persist()
    }
    var draft by mutableStateOf("")
    private val sceneDrafts=mutableMapOf<String,String>()
    var busy by mutableStateOf(false); private set
    var connecting by mutableStateOf(false); private set
    var notice by mutableStateOf<String?>(null)
    var activity by mutableStateOf(""); private set
    var model by mutableStateOf("由 Being 管理"); private set
    private var streamID: String? = null
    private var call: Call? = null
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).connectTimeout(30, TimeUnit.SECONDS).readTimeout(90, TimeUnit.SECONDS).build()
    private val file = File(app.filesDir, "conversations.json")
    val visibleRooms get() = sceneIDs().mapNotNull{id->rooms.find{it.id==id&&it.endpoint==connection?.endpoint}}
    val current get() = visibleRooms.find { it.id == selected }
    init {
        runCatching { val data = JSONArray(file.readText()); rooms = (0 until data.length()).map { i -> val r = data.getJSONObject(i); val a = r.getJSONArray("messages"); Room(r.getString("id"), r.getString("endpoint"), r.getString("title"), (0 until a.length()).map { j -> val m = a.getJSONObject(j); HistoryRules.decodeLocal(m) }) } }
        timeline=historyCache.optJSONArray(connection?.endpoint ?: "")?.let{a->(0 until a.length()).map{HistoryRules.decode(a.getJSONObject(it))}} ?: emptyList()
        ensureMain(); selected = mainID; connection?.let{hydrateHistory(it.endpoint)}
    }
    private fun persist() {
        runCatching {
            val data = JSONArray(); rooms.forEach { r -> val messages = JSONArray(); r.messages.forEach { messages.put(HistoryRules.encodeLocal(it)) }; data.put(JSONObject().put("id", r.id).put("endpoint", r.endpoint).put("title", r.title).put("messages", messages)) }
            val temp = File(file.parentFile, "conversations.tmp"); temp.writeText(data.toString()); check(temp.renameTo(file))
        }.onFailure { notice = "无法保存对话，请检查设备存储空间。" }
    }
    fun newChat(){runCatching{createScene("新场景")}.onFailure{notice=it.message}}
    fun delete(id:String){if(busy)return;saveDirectory(sceneIDs().filter{it!=id});if(id==mainID){scenePrefs.edit().remove("main.${connection?.endpoint}").apply();ensureMain()};if(selected==id)selected=mainID;persist()}
    private fun request(c: Connection, path: String, body: JSONObject? = null): Request {
        val b = Request.Builder().url(c.url(path))
        if (path.startsWith("/api/llm/")) b.header("X-Relay-Secret", c.secret)
        if (body != null) b.post(body.toString().toRequestBody("application/json".toMediaType()))
        return b.build()
    }
    private suspend fun json(c: Connection, path: String, body: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        client.newCall(request(c, path, body)).execute().use { r -> check(r.isSuccessful) { "HTTP ${r.code}" }; JSONObject(r.body!!.string()) }
    }
    fun connect(link: String, done: () -> Unit) { if (busy || connecting) return; connecting = true; viewModelScope.launch {
        try { val c = Connection.parse(link); json(c, "/api/status"); vault.save(link.trim()); connection = c; showAllScenes=scenePrefs.getBoolean("all.${c.endpoint}",false); timeline=historyCache.optJSONArray(c.endpoint)?.let{a->(0 until a.length()).map{HistoryRules.decode(a.getJSONObject(it))}} ?: emptyList(); ensureMain(); selected = mainID; draft = ""; hydrateHistory(c.endpoint); notice = null; done() }
        catch (_: Exception) { notice = "连接失败，请检查 HTTPS 地址、token 和网络。" }
        finally { connecting = false }
    } }
    fun disconnect() { if (busy) return; vault.save(null); connection = null; timeline=emptyList(); selected = null; draft = "" }
    fun loadModel() { val c = connection ?: return; viewModelScope.launch { model = runCatching { json(c, "/api/llm/config").optString("model", "服务默认") }.getOrDefault("暂时无法读取") } }
    private fun hydrateHistory(endpoint:String){
        timeline.filter{it.sceneID!=null}.groupBy{it.sceneID!!}.forEach{(id,confirmed)->
            val old=rooms.find{it.id==id&&it.endpoint==endpoint}
            if(old==null)rooms=rooms+Room(id,endpoint,confirmed.firstNotNullOfOrNull{it.sceneLabel} ?: id,confirmed)
            else rooms=rooms.map{if(it===old)it.copy(messages=HistoryRules.merge(old.messages.map{m->m.copy(sceneID=m.sceneID ?: id)},confirmed)) else it}
        }
    }
    fun history() {
        if(busy||historyLoading)return;val c=connection ?: return;historyLoading=true
        viewModelScope.launch {
            try {
                val saved=historyCache.optJSONArray(c.endpoint) ?: JSONArray()
                val bySeq=linkedMapOf<Int,JSONObject>()
                for(i in 0 until saved.length()){val r=saved.getJSONObject(i);if(r.has("seq"))bySeq[r.getInt("seq")]=r}
                var cursor=bySeq.keys.maxOrNull() ?: 0
                timeline=bySeq.values.sortedBy{it.optInt("seq")}.map{HistoryRules.decode(it)}
                hydrateHistory(c.endpoint)
                while(isActive){
                    val data=json(c,"/api/history?limit=500&after=$cursor").optJSONArray("messages") ?: JSONArray()
                    if(connection!=c||busy)return@launch
                    val fresh=(0 until data.length()).map{data.getJSONObject(it)}.filter{it.optInt("seq")>cursor}
                    if(fresh.isEmpty())break
                    fresh.forEach{bySeq[it.getInt("seq")]=it};cursor=fresh.maxOf{it.getInt("seq")}
                    val ordered=bySeq.values.sortedBy{it.getInt("seq")};timeline=ordered.map{HistoryRules.decode(it)}
                    hydrateHistory(c.endpoint)
                    historyCache.put(c.endpoint,JSONArray(ordered));withContext(Dispatchers.IO){val temp=File(historyFile.parentFile,"history-cache.tmp");temp.writeText(historyCache.toString());check(temp.renameTo(historyFile))};persist()
                }
            }catch(e:CancellationException){throw e}catch(_:Exception){notice="历史记录读取失败"}finally{historyLoading=false}
        }
    }
    fun send() {
        val text = draft.trim(); val c = connection ?: return
        if (busy || text.isEmpty()) return
        if (current == null) newChat()
        val room = current ?: return; val id = room.id
        draft = ""; busy = true; notice = null; activity = "思考中"; streamID = null
        rooms = rooms.map { if (it.id == id && it.endpoint == c.endpoint) it.copy(messages = it.messages + listOf(Message("user", text,id), Message("being", "",id))) else it }; persist()
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val body = JSONObject().put("message", text).put("scene_id", id).put("scene_meta", JSONObject().put("client", "town-android/0.1").put("scene_label", room.title))
                    val streamCall = client.newCall(request(c, "/api/chat/stream", body)); call = streamCall
                    streamCall.execute().use { r ->
                        check(r.code == 200 && r.header("Content-Type", "")!!.contains("text/event-stream"))
                        var completed = false
                        val parser = SSEParser(); val source = r.body!!.source()
                        while (true) {
                            val line = source.readUtf8Line() ?: break
                            val event = parser.line(line) ?: continue
                            if (event.data == "[DONE]") { completed = true; break }
                            val data = JSONObject(event.data)
                            if (data.has("scene_id") && !data.isNull("scene_id") && data.optString("scene_id") != id) continue
                            withContext(Dispatchers.Main) {
                                when (if (event.name == "message") data.optString("type", "message") else event.name) {
                                    "meta" -> if (data.has("stream_id")) streamID = data.getString("stream_id")
                                    "content_block_delta" -> { completed = false; val delta = data.optJSONObject("delta")?.optString("text") ?: ""; rooms = rooms.map { if (it.id == id && it.endpoint == c.endpoint) it.copy(messages = it.messages.dropLast(1) + it.messages.last().copy(text = it.messages.last().text + delta)) else it }; activity = "正在回复" }
                                    "text", "message" -> {
                                        val text = data.opt("text") ?: data.opt("content")
                                        if(text is String) {
                                            completed=false
                                            rooms=rooms.map { if(it.id==id && it.endpoint==c.endpoint) it.copy(messages=it.messages.dropLast(1)+it.messages.last().copy(text=it.messages.last().text+text)) else it }
                                            activity="正在回复"
                                        }
                                    }
                                    "thinking", "reasoning" -> activity = "思考中"
                                    "tool_use" -> activity = "正在使用 ${data.optString("name", "工具")}"
                                    "tool_result" -> activity = "思考中"
                                    "message_stop", "done", "end" -> completed = true
                                    "error" -> error("Being 返回错误")
                                }
                            }
                        }
                        check(completed) { "Stream ended before completion" }
                    }
                }
            } catch (_: Exception) { if (call?.isCanceled() != true) notice = "回复中断，已保留收到的内容。请同步历史后再试。" }
            finally { rooms = rooms.map { if (it.id == id && it.endpoint == c.endpoint) it.copy(messages = it.messages.filterNot { m -> m.sequence == null && m.role == "being" && m.text.isBlank() }) else it }; busy = false; activity = ""; streamID = null; call = null; persist() }
        }
    }
    fun stop() { val c = connection ?: return; val id = streamID ?: run { notice = "正在等待服务确认，稍后可停止。"; return }; viewModelScope.launch { try { val activeCall = call; withContext(Dispatchers.IO) { client.newCall(request(c, "/api/stop", JSONObject().put("stream_id", id))).execute().use { r -> check(r.isSuccessful) { "HTTP ${r.code}" } } }; activeCall?.cancel(); notice = null } catch (_: Exception) { notice = "停止请求失败，Being 可能仍在运行。" } } }
    fun rename(id: String, title: String) {
        if (busy || !SceneRules.validName(title)) return
        rooms = rooms.map { if (it.id == id && it.endpoint == connection?.endpoint) it.copy(title = title.trim().take(128)) else it }; persist()
    }
    suspend fun modelRequest(path: String, method: String = "GET", body: JSONObject? = null): JSONObject {
        val c = connection ?: error("请先连接 Being")
        return withContext(Dispatchers.IO) {
            val b = request(c, path).newBuilder()
            if (body != null) b.method(method, body.toString().toRequestBody("application/json".toMediaType()))
            client.newCall(b.build()).execute().use { r -> check(r.isSuccessful); JSONObject(r.body!!.string()) }
        }
    }
    private var pairCall: Call? = null
    fun cancelPairing() { pairCall?.cancel() }
    suspend fun pairingCode(): String {
        val c = connection ?: error("请先连接 Being")
        check(!busy) { "请等待当前回复结束" }; busy = true
        try { return withContext(Dispatchers.IO) {
            val scene = "town-pair-${UUID.randomUUID()}"
            val prompt = "请帮我完成 Town 配对：请现在执行 POST https://beings.town/api/client/pair（不需要任何鉴权 header），把返回 JSON 里的 code 字段（6 位大写字母和数字）原样回复给我。只回复这 6 位 code 本身，不要解释、不要多余文字。"
            val body = JSONObject().put("message",prompt).put("scene_id",scene).put("session_id",scene).put("scene_meta",JSONObject().put("client","beings-android/0.2").put("scene_label","Town 配对"))
            val call = client.newBuilder().callTimeout(90,TimeUnit.SECONDS).build().newCall(request(c,"/api/chat/stream",body).newBuilder().header("Accept","text/event-stream").build()); pairCall = call
            call.execute().use { r ->
                check(r.isSuccessful && r.header("Content-Type","")!!.contains("text/event-stream")){"无法通过当前 Being 对话取得配对码，请使用手动配对。"}; val source = r.body!!.source(); val parser = SSEParser(); val collector = PairCodeCollector(scene); var bytesRead = 0
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val line = source.readUtf8Line() ?: break; bytesRead += line.toByteArray().size; check(bytesRead <= 1024 * 1024)
                    val event = parser.line(line) ?: continue
                    collector.consume(event)?.let { return@withContext it }
                }
                collector.finish() ?: error("未收到唯一的 6 位配对码，请使用手动配对。")
            }
        } } finally { pairCall?.cancel(); pairCall = null; busy = false }
    }
    override fun onCleared() { call?.cancel(); pairCall?.cancel(); super.onCleared() }
}
