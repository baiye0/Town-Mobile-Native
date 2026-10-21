package town.nativeapp

import android.app.Application
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONArray
import org.json.JSONObject
import android.util.Base64
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

data class Message(val role: String, val text: String, val sceneID:String?=null,val sequence:Int?=null,val kind:String?=null,val timestamp:String?=null,val sceneLabel:String?=null,val files:List<PendingAttachment>?=null,val process:String?=null,
    val id:String=UUID.randomUUID().toString(),val localBaseline:Int?=null,val replyTo:String?=null,val localAfter:String?=null,val streaming:Boolean?=null,val persistedText:String?=null)
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
    private val displayState = derivedStateOf {
        (if(showAllScenes) HistoryRules.merge(rooms.filter{it.endpoint==connection?.endpoint}.flatMap{r->r.messages.map{it.copy(sceneID=it.sceneID ?: r.id)}},timeline,activeMessageIDs)
        else HistoryRules.ordered(current?.messages.orEmpty()+if(showSBS)timeline.filter{it.sceneID==null&&it.role!="user"}else emptyList()))
            .filter { it.text.isNotBlank() || !it.files.isNullOrEmpty() }
    }
    val displayMessages get() = displayState.value
    private val activeMessageIDs get()=outbox.flatMap{listOf(it.userID,it.replyID)+it.bubbles.orEmpty().map{b->b.id}}.toSet()
    private fun sceneIDs():List<String>{val a=directory.optJSONArray(connection?.endpoint ?: "") ?: JSONArray();return (0 until a.length()).map{a.getString(it)}}
    private fun saveDirectory(ids:List<String>){val c=connection ?: return;val next=JSONObject(directory.toString());next.put(c.endpoint,JSONArray(ids));directory=next;scenePrefs.edit().putString("directory",next.toString()).apply()}
    private fun ensureMain(){
        val c=connection ?: return
        val id=mainID ?: "mobile-${UUID.randomUUID()}".also{scenePrefs.edit().putString("main.${c.endpoint}",it).apply()}
        if(rooms.none{it.id==id&&it.endpoint==c.endpoint})rooms=listOf(Room(id,c.endpoint,"主对话"))+rooms
        val ids=if(directory.has(c.endpoint))sceneIDs() else rooms.filter{it.endpoint==c.endpoint&&it.id.startsWith("mobile-")}.map{it.id}
        saveDirectory(listOf(id)+ids.filter{it!=id})
    }
    fun selectScene(id:String){if(visibleRooms.none{it.id==id})return;sceneDrafts["${connection?.endpoint}|$selected"]=draft;sceneAttachments["${connection?.endpoint}|$selected"]=attachments;selected=id;attachments=sceneAttachments["${connection?.endpoint}|$id"] ?: emptyList();draft=sceneDrafts["${connection?.endpoint}|$id"] ?: "";showSBS=scenePrefs.getBoolean("sbs.${connection?.endpoint}|$id",false)}
    fun sceneName(message:Message)=message.sceneID?.let{id->rooms.find{it.id==id&&it.endpoint==connection?.endpoint}?.title ?: message.sceneLabel ?: id} ?: "全局消息"
    fun getSBSVisibility()=scenePrefs.getBoolean("sbs.${connection?.endpoint}|$selected",false)
    fun saveSBS(){scenePrefs.edit().putBoolean("sbs.${connection?.endpoint}|$selected",showSBS).apply()}
    fun createScene(name:String,binding:String?=null){
        val c=connection ?: return
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
    var intelligentUI by mutableStateOf(false)
    var draft by mutableStateOf("")
    private val sceneDrafts=mutableMapOf<String,String>()
    private val sceneAttachments=mutableMapOf<String,List<PendingAttachment>>()
    var busy by mutableStateOf(false); private set
    var connecting by mutableStateOf(false); private set
    var notice by mutableStateOf<String?>(null)
    var sbsActivity by mutableStateOf("");private set
    var sbsEnabled by mutableStateOf<Boolean?>(null);private set
    var sbsUpdating by mutableStateOf(false);private set
    var sbsError by mutableStateOf<String?>(null);private set
    private var sbsConnection:Connection?=null
    private var sbsRevision=0
    val sbsStatus get()=sbsActivity.ifEmpty{when(sbsEnabled){true->"SBS 待命中";false->"SBS 已关闭";null->"SBS 状态待同步"}}
    suspend fun syncSBS() {
        val c=connection ?: return
        if(sbsConnection!=c){sbsConnection=c;sbsEnabled=null;sbsActivity="";sbsError=null;sbsRevision++}
        val revision=sbsRevision
        try {
            val config=try{json(c,"/api/llm/config")}catch(e:CancellationException){throw e}catch(_:Exception){null}
            if(connection!=c)return
            if(revision==sbsRevision&&!sbsUpdating)(config?.opt("sbs_enabled") as? Boolean)?.let{sbsEnabled=it}
            val status=withContext(Dispatchers.IO){client.newCall(request(c,"/api/stream/active")).execute().use{r->
                when(r.code){204->"";200->HistoryRules.sbsStatus(JSONObject(r.body!!.string()));else->null}
            }}
            if(connection!=c)return
            if(status!=null)sbsActivity=status
            if(showSBS||showAllScenes)history()
        }catch(e:CancellationException){throw e}catch(_:Exception){/* Retain last confirmed state. */}
    }
    fun setSBSEnabled(enabled:Boolean) {
        val c=connection ?: return
        if(sbsEnabled==null||sbsUpdating||sbsConnection!=c)return
        sbsUpdating=true;sbsRevision++
        viewModelScope.launch {
            try {
                val result=withContext(Dispatchers.IO){
                    val body=JSONObject().put("sbs_enabled",if(enabled)"on" else "off").toString().toRequestBody("application/json".toMediaType())
                    client.newCall(request(c,"/api/llm/config").newBuilder().patch(body).build()).execute().use{r->check(r.isSuccessful);JSONObject(r.body!!.string())}
                }
                if(connection!=c)return@launch
                check(result.optBoolean("ok") && result.optJSONObject("config")?.opt("sbs_enabled") is Boolean)
                sbsEnabled=result.getJSONObject("config").getBoolean("sbs_enabled");sbsError=null
            }catch(e:CancellationException){throw e}catch(_:Exception){if(connection==c)sbsError="SBS 设置未保存，请重试。"}finally{sbsUpdating=false}
        }
    }
    var activity by mutableStateOf(""); private set
    var activeSendID by mutableStateOf<String?>(null); private set
    var submittedMessageID by mutableStateOf<String?>(null); private set
    var streamingReplyID by mutableStateOf<String?>(null); private set
    var model by mutableStateOf("由 Being 管理"); private set
    private var streamID: String? = null
    private var call: Call? = null
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).connectTimeout(30, TimeUnit.SECONDS).readTimeout(90, TimeUnit.SECONDS).build()
    private val file = File(app.filesDir, "conversations.json")
    val visibleRooms get() = sceneIDs().mapNotNull{id->rooms.find{it.id==id&&it.endpoint==connection?.endpoint}}
    val current get() = visibleRooms.find { it.id == selected }
    private val outboxFile=File(getApplication<Application>().filesDir,"outbox.json")
    private var outboxUnavailable=false
    var outbox by mutableStateOf<List<PendingSend>>(emptyList());private set
    var attachments by mutableStateOf<List<PendingAttachment>>(emptyList())
    var activeScene by mutableStateOf<String?>(null);private set
    var appActive by mutableStateOf(true)
    var chatVisible=true
    private var worker:Job?=null
    val visibleOutbox get()=outbox.filter{it.endpoint==connection?.endpoint}
    init {
        loadOutbox()
        runCatching { val data = JSONArray(file.readText()); rooms = (0 until data.length()).map { i -> val r = data.getJSONObject(i); val a = r.getJSONArray("messages"); Room(r.getString("id"), r.getString("endpoint"), r.getString("title"), (0 until a.length()).map { j -> val m = a.getJSONObject(j); HistoryRules.decodeLocal(m) }) } }
        timeline=historyCache.optJSONArray(connection?.endpoint ?: "")?.let{a->(0 until a.length()).map{HistoryRules.decode(a.getJSONObject(it))}} ?: emptyList()
        ensureMain(); selected = mainID; showSBS=scenePrefs.getBoolean("sbs.${connection?.endpoint}|$selected",false); connection?.let{hydrateHistory(it.endpoint)}
        visibleOutbox.forEach{project(it)}
    }
    private fun persist():Boolean {
        return runCatching {
            val data = JSONArray(); rooms.forEach { r -> val messages = JSONArray(); r.messages.forEach { messages.put(HistoryRules.encodeLocal(it)) }; data.put(JSONObject().put("id", r.id).put("endpoint", r.endpoint).put("title", r.title).put("messages", messages)) }
            val temp = File(file.parentFile, "conversations.tmp"); temp.writeText(data.toString()); check(temp.renameTo(file))
        }.onFailure { notice = "无法保存对话，请检查设备存储空间。" }.isSuccess
    }
    fun newChat(){runCatching{createScene("新场景")}.onFailure{notice=it.message}}
    fun delete(id:String){if(busy)return;if(outbox.any{it.endpoint==connection?.endpoint&&it.sceneID==id}){notice="请先处理该场景的发送队列。";return};saveDirectory(sceneIDs().filter{it!=id});if(id==mainID){scenePrefs.edit().remove("main.${connection?.endpoint}").apply();ensureMain()};if(selected==id)selected=mainID;persist()}
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
        try { val c = Connection.parse(link); json(c, "/api/status"); PortalRuntime.stop(getApplication()); vault.save(link.trim()); AndroidPortalRestoreJob.enqueue(getApplication()); connection = c; showAllScenes=scenePrefs.getBoolean("all.${c.endpoint}",false); timeline=historyCache.optJSONArray(c.endpoint)?.let{a->(0 until a.length()).map{HistoryRules.decode(a.getJSONObject(it))}} ?: emptyList(); ensureMain(); selected = mainID; draft = ""; attachments=emptyList(); hydrateHistory(c.endpoint); notice = null; done() }
        catch (_: Exception) { notice = "连接失败，请检查 HTTPS 地址、token 和网络。" }
        finally { connecting = false }
    } }
    fun disconnect() { if (busy) return; PortalRuntime.stop(getApplication()); vault.save(null); AndroidPortalRestoreJob.enqueue(getApplication()); connection = null; timeline=emptyList(); selected = null; draft = ""; attachments=emptyList() }
    fun loadModel() { val c = connection ?: return; viewModelScope.launch { model = runCatching { json(c, "/api/llm/config").optString("model", "服务默认") }.getOrDefault("暂时无法读取") } }
    private fun hydrateHistory(endpoint:String){
        timeline.filter{it.sceneID!=null}.groupBy{it.sceneID!!}.forEach{(id,confirmed)->
            val old=rooms.find{it.id==id&&it.endpoint==endpoint}
            if(old==null)rooms=rooms+Room(id,endpoint,confirmed.firstNotNullOfOrNull{it.sceneLabel} ?: id,confirmed)
            else rooms=rooms.map{if(it===old)it.copy(messages=HistoryRules.merge(old.messages.map{m->m.copy(sceneID=m.sceneID ?: id)},confirmed,activeMessageIDs)) else it}
        }
    }
    fun history() {
        if(historyLoading)return;val c=connection ?: return;historyLoading=true
        viewModelScope.launch {
            try {
                val saved=historyCache.optJSONArray(c.endpoint) ?: JSONArray()
                val bySeq=linkedMapOf<Int,JSONObject>()
                for(i in 0 until saved.length()){val r=saved.getJSONObject(i);if(r.has("seq"))bySeq[r.getInt("seq")]=r}
                var cursor=bySeq.keys.maxOrNull() ?: 0
                val initial=cursor==0
                if(notice?.startsWith("历史记录")==true)notice=null
                timeline=bySeq.values.sortedBy{it.optInt("seq")}.map{HistoryRules.decode(it)}
                hydrateHistory(c.endpoint)
                while(isActive){
                    val data=json(c,HistoryRules.requestPath(cursor)).getJSONArray("messages")
                    if(connection!=c)return@launch
                    val fresh=(0 until data.length()).map{data.getJSONObject(it)}.filter{it.optInt("seq")>cursor}
                    if(fresh.isEmpty())break
                    fresh.forEach{bySeq[it.getInt("seq")]=it};cursor=fresh.maxOf{it.getInt("seq")}
                    val ordered=bySeq.values.sortedBy{it.getInt("seq")};timeline=ordered.map{HistoryRules.decode(it)}
                    hydrateHistory(c.endpoint)
                    historyCache.put(c.endpoint, JSONArray(ordered))
                    try { withContext(Dispatchers.IO) {
                        val temp = File(historyFile.parentFile, "history-cache.tmp")
                        temp.writeText(historyCache.toString())
                        check(temp.renameTo(historyFile))
                    } } catch(e:CancellationException){throw e} catch(_:Exception){notice="历史记录已加载，但缓存保存失败，请检查设备存储空间。"}
                    persist()
                    if(initial)break
                }
                if(notice=="发送未完成，请查看发送队列。")notice=null
            }catch(e:CancellationException){throw e}catch(e:Exception){if(connection==c)notice=HistoryRules.failureMessage(e)}finally{historyLoading=false}
        }
    }
    fun loadOutbox(){if(outboxFile.exists())runCatching{val a=JSONArray(outboxFile.readText());outbox=(0 until a.length()).map{PendingSend.read(a.getJSONObject(it))}}.onFailure{outboxUnavailable=true;notice="发送队列无法读取，已保留原文件；请先恢复队列文件。"}}
    private fun saveOutbox(){val temp=File(outboxFile.parentFile,"outbox.tmp");temp.writeText(JSONArray(outbox.map{it.json()}).toString());check(temp.renameTo(outboxFile)){"无法保存发送队列"}}
    fun send(){
        if(outboxUnavailable)return;val c=connection ?: return;val text=draft.trim();if(text.isEmpty()&&attachments.isEmpty())return
        if(current==null)newChat();val room=current ?: return
        val entry=PendingSend(endpoint=c.endpoint,sceneID=room.id,title=room.title,text=text,files=attachments.toMutableList(),baseline=timeline.mapNotNull{it.sequence}.maxOrNull() ?: 0,intelligentUI=intelligentUI,afterID=room.messages.lastOrNull{it.text.isNotBlank()||!it.files.isNullOrEmpty()}?.id)
        outbox=outbox+entry
        try{saveOutbox();project(entry);persist();submittedMessageID=entry.userID;draft="";attachments=emptyList();intelligentUI=false;startDelivery()}catch(_:Exception){outbox=outbox.filter{it.id!=entry.id};notice="无法保存发送队列，草稿已保留。"}
    }
    fun changeQueued(id:String,text:String?=null,move:Int=0,remove:Boolean=false){
        val index=outbox.indexOfFirst{it.id==id};if(index<0)return;val entry=outbox[index]
        if(entry.phase !in listOf("queued","failed","unknown","stopped"))return
        val old=outbox.map{PendingSend.read(it.json())}
        if(remove)outbox=outbox.filter{it.id!=id}
        else if(DeliveryRules.canEdit(entry.phase)){
            if(entry.files.isEmpty()&&!text.isNullOrBlank()){entry.text=text.trim();entry.preparedText=null}
            if(move!=0){val peers=outbox.indices.filter{outbox[it].endpoint==entry.endpoint&&outbox[it].phase=="queued"};val p=peers.indexOf(index);if(p+move in peers.indices){val list=outbox.toMutableList();java.util.Collections.swap(list,index,peers[p+move]);outbox=list}}
        }
        try{outbox=outbox.map{it.copy()};saveOutbox();if(remove)rooms=rooms.map{r->if(r.endpoint==entry.endpoint&&r.id==entry.sceneID)r.copy(messages=r.messages.filterNot{it.sequence==null&&(it.id==entry.userID||it.replyTo==entry.userID||it.kind in listOf(entry.userID,entry.replyID))}) else r} else project(entry);persist();if(remove&&notice=="发送未完成，请查看发送队列。"&&!visibleOutbox.any{it.phase in listOf("failed","unknown")})notice=null;startDelivery()}catch(_:Exception){outbox=old;notice="无法保存队列修改。"}
    }
    fun retryQueued(id:String){val entry=outbox.find{it.id==id&&it.phase=="failed"} ?: return;entry.phase="queued";entry.error=null;entry.files.filter{it.attachmentID!=null&&it.jobID==null}.forEach{it.forceParse=true};try{saveOutbox();startDelivery()}catch(_:Exception){entry.phase="failed";notice="无法保存发送状态。"}}
    fun resumeDelivery(){startDelivery(true)}
    private fun checkpoint(entry:PendingSend){outbox=outbox.map{if(it.id==entry.id)entry.copy() else it};saveOutbox()}
    private fun project(entry:PendingSend){
        rooms=rooms.map{room->if(room.id!=entry.sceneID||room.endpoint!=entry.endpoint)room else room.copy(messages=ReplyStream.project(room.messages,entry))}
        if(busy&&activeSendID==entry.id&&entry.phase in listOf("sending","waiting"))ReplyStream.messages(entry).lastOrNull{it.text.isNotEmpty()}?.let{streamingReplyID=it.id}
    }
    private fun consume(type:String,data:JSONObject,entry:PendingSend){
        if(data.has("scene_id")&&data.isNull("scene_id")){sbsActivity=if(type in listOf("message_stop","done","end"))"" else "正在自主活动";return}
        if(data.nullString("scene_id")?.let{it!=entry.sceneID}==true)return
        data.nullString("stream_id")?.let{entry.streamID=it;streamID=it}
        ReplyStream.consume(type,data,entry)
        when(type){
            "content_block_delta"->{val delta=data.optJSONObject("delta");if(!(delta?.opt("text") as? String).isNullOrEmpty())activity="正在回复" else (delta?.opt("thinking") as? String)?.takeIf{it.isNotEmpty()}?.let{entry.process+=it;activity="思考中"}}
            "text","message"->{if(!((data.opt("text") ?: data.opt("content")) as? String).isNullOrEmpty())activity="正在回复"}
            "thinking","reasoning"->{activity="思考中";entry.process+=ReplyStream.reasoningText(data)}
            "tool_use"->{activity="正在使用 ${data.optString("name","工具")}";entry.process+="\n$activity\n${data.opt("input") ?: ""}"}
            "tool_result"->{entry.process+="\n${data.opt("content") ?: data.opt("result") ?: ""}";activity="思考中"}
            "message_stop"->{if(!ReplyStream.hasFinalReply(entry))activity="等待最终回复"}
            "error"->error("Being 返回错误")
        };entry.process=entry.process.takeLast(64000)
    }
    private fun startDelivery(recover:Boolean=false){
        if(outboxUnavailable||worker!=null||busy)return;val c=connection ?: return
        val endpointItems=outbox.withIndex().filter{it.value.endpoint==c.endpoint}
        var head=0
        while(head<endpointItems.size&&endpointItems[head].value.phase in listOf("failed","stopped"))head++
        if(head>=endpointItems.size)return
        val first=endpointItems[head].value
        if(first.phase !in listOf("queued","preparing")&&!(recover&&first.phase in listOf("sending","waiting","unknown")))return
        busy=true;activeScene=first.sceneID;activeSendID=first.id
        worker=viewModelScope.launch {
            val entry=PendingSend.read(first.json());var safe=false
            try{
                if(entry.phase in listOf("queued","preparing")){
                    entry.phase="preparing";checkpoint(entry)
                    entry.preparedText=null
                    activity="准备发送"
                    // Town Client renders the local user turn before upload.
                    // Keep the attachment card in that bubble while the
                    // upload and parser advance.
                    project(entry)
                    if(entry.files.isNotEmpty())entry.preparedText=prepareFiles(entry,c)
                    if(entry.intelligentUI)entry.preparedText=(entry.preparedText ?: entry.text)+NativeUI.context
                    entry.baseline=historyBaseline(c,entry.baseline)
                    entry.attachmentMessageID?.let{attachmentJSON(c,"/api/attachment-messages/$it",JSONObject().put("delivery_status","sending"))}
                    entry.phase="sending";checkpoint(entry);project(entry)
                    try{
                        withContext(Dispatchers.IO){
                            val body=JSONObject().put("message",entry.preparedText ?: entry.text).put("scene_id",entry.sceneID).put("scene_meta",JSONObject().put("client","being-android/0.3").put("scene_label",entry.title))
                            val active=client.newBuilder().callTimeout(10,TimeUnit.MINUTES).build().newCall(request(c,"/api/chat/stream",body));call=active
                            active.execute().use{r->
                                entry.attachmentMessageID?.let{runCatching{attachmentJSON(c,"/api/attachment-messages/$it",JSONObject().put("delivery_status",if(r.isSuccessful)"accepted" else if(r.code in 400..499)"failed" else "unknown"))}}
                                if(r.code==202){withContext(Dispatchers.Main){entry.phase="waiting";checkpoint(entry)}}else{
                                    if(r.code!=200){if(r.code in 400..499)entry.phase="failed";error("HTTP ${r.code}")}
                                    check(r.header("Content-Type","")!!.contains("text/event-stream"))
                                    val parser=SSEParser();val source=r.body!!.source();var complete=false;var lastSaved=0L
                                    val presentation=StreamPresentation(viewModelScope){project(it)}
                                    suspend fun handleEvent(event:SSEEvent){
                                        if(event.data=="[DONE]"){complete=true;return}
                                        val data=ReplyStream.payload(event) ?: return;val type=if(event.name=="message")data.optString("type","message") else event.name
                                        withContext(Dispatchers.Main) consumeEvent@ {
                                            if(DeliveryRules.countsForReplay(type,data.optBoolean("continuation"),data.has("persisted")))entry.cursor++
                                            consume(type,data,entry)
                                            if(data.has("scene_id")&&data.nullString("scene_id")!=entry.sceneID)return@consumeEvent
                                            if(type in listOf("done","end"))complete=true else if(type in listOf("text","content_block_delta","tool_use","thinking","reasoning"))complete=false
                                            if(System.currentTimeMillis()-lastSaved>500){checkpoint(entry);lastSaved=System.currentTimeMillis()};presentation.submit(entry)
                                        }
                                    }
                                    try { while(true){
                                        ensureActive();val line=source.readUtf8Line() ?: break;check(line.length<=1024*1024)
                                        val event=parser.line(line) ?: continue
                                        handleEvent(event)
                                    }
                                    // Flush an SSE frame that ended at EOF and
                                    // treat EOF as the end of the turn, as the
                                    // Town Client does when [DONE] is omitted.
                                    parser.line("")?.let{handleEvent(it)}
                                    withContext(Dispatchers.Main){ReplyStream.finish(entry);presentation.submit(entry)}
                                    if(!complete&&ReplyStream.hasFinalReply(entry))complete=true
                                    safe=complete&&ReplyStream.hasFinalReply(entry)
                                    } finally { withContext(NonCancellable+Dispatchers.Main){presentation.flush()} }
                                }
                            }
                        }
                    }catch(e:CancellationException){throw e}catch(e:Exception){if(entry.phase=="failed")throw e;activity="正在恢复连接"}
                }
                if(!safe){project(entry);safe=this@TownModel.recover(entry,c)}
                if(safe){try{reconcile(entry,c)}catch(e:CancellationException){throw e}catch(_:Exception){};check(persist()){ "无法保存已完成的回复" };val previous=outbox;outbox=outbox.filter{it.id!=entry.id};try{saveOutbox()}catch(e:Exception){outbox=previous;throw e};if(notice=="发送未完成，请查看发送队列。")notice=null;CompletionNotifications.finished(getApplication(),c.endpoint,entry.sceneID,entry.title,!appActive||!chatVisible||selected!=entry.sceneID)}
                else{entry.phase="unknown";entry.error="发送结果待确认；可同步历史或移除本地等待记录，不会自动重发。";checkpoint(entry)}
            }catch(e:CancellationException){if(outbox.find{it.id==entry.id}?.phase=="stopped"){entry.phase="stopped";ReplyStream.finish(entry);runCatching{checkpoint(entry);project(entry)}};throw e}catch(e:Exception){entry.phase=if(entry.phase in listOf("queued","preparing","failed"))"failed" else "unknown";entry.error=e.message;runCatching{checkpoint(entry);project(entry)};if(notice=="发送未完成，请查看发送队列。")notice=null}
            finally{busy=false;activeScene=null;activeSendID=null;streamingReplyID=null;streamID=null;activity="";call=null;worker=null;persist();startDelivery()}
        }
    }
    private suspend fun recover(entry:PendingSend,c:Connection):Boolean{
        activity="正在恢复回复"
        var idleSince=System.currentTimeMillis();var attempt=0;var failures=0
        while(System.currentTimeMillis()-idleSince<300000){
            currentCoroutineContext().ensureActive()
            try{
                val response=withContext(Dispatchers.IO){client.newCall(request(c,"/api/stream/active?after=${entry.cursor}")).execute().use{it.code to it.body?.string()}}
                if(response.first==204)return reconcile(entry,c)
                check(response.first==200);val data=JSONObject(response.second ?: "{}")
                val id=data.nullString("stream_id")
                if(entry.streamID!=null&&entry.streamID!=id)return reconcile(entry,c)
                if(entry.streamID==null&&data.nullString("scene_id")!=entry.sceneID){if(reconcile(entry,c))return true}
                else{
                    entry.streamID=id;streamID=id;val events=data.optJSONArray("events") ?: JSONArray()
                    if(events.length()>0&&events.getJSONObject(0).optInt("seq")>entry.cursor+1)return reconcile(entry,c)
                    for(i in 0 until events.length()){val event=events.getJSONObject(i);val seq=event.optInt("seq");if(seq<=entry.cursor)continue;val type=event.optString("event");val value=event.optJSONObject("data") ?: JSONObject();if(ReplyStream.isProgress(type,value,entry.sceneID))idleSince=System.currentTimeMillis();consume(type,value,entry);entry.cursor=seq}
                    checkpoint(entry);project(entry)
                    if(data.optBoolean("finished"))return reconcile(entry,c)
                }
                failures=0
            }catch(e:CancellationException){throw e}catch(e:Exception){failures++;if(failures>=5)throw e}
            attempt++;delay(minOf(5000L,1000L+attempt/3*1000L))
        };return false
    }
    private suspend fun historyBaseline(c:Connection,after:Int):Int {
        var cursor=after
        while(true){val a=json(c,"/api/history?limit=500&after=$cursor").optJSONArray("messages") ?: JSONArray();val next=(0 until a.length()).map{a.getJSONObject(it).optInt("seq")}.maxOrNull() ?: cursor;if(next<=cursor)return cursor;cursor=next}
    }
    private suspend fun reconcile(entry:PendingSend,c:Connection):Boolean{
        var cursor=entry.baseline;var sawUser=false;val reply=StringBuilder();var ended=false;val confirmed=mutableListOf<Message>()
        while(!ended){
            val result=json(c,"/api/history?limit=500&after=$cursor").optJSONArray("messages") ?: JSONArray()
            val rows=(0 until result.length()).map{result.getJSONObject(it)}.filter{it.optInt("seq")>cursor}.sortedBy{it.optInt("seq")}
            if(rows.isEmpty())break
            for(row in rows.filter{it.nullString("scene_id")==entry.sceneID}){
                val text=HistoryRules.text(row.opt("content"))
                if(row.optString("role")=="user"){if(sawUser){ended=true;break};sawUser=DeliveryRules.matchesSubmittedText(text,entry.preparedText ?: entry.text);if(sawUser)confirmed.add(HistoryRules.decode(row).copy(files=entry.files))}
                else if(sawUser&&row.optString("type")!="marker"&&row.optString("from")!="system"){if(reply.isNotEmpty())reply.append("\n\n");reply.append(text);confirmed.add(HistoryRules.decode(row))}
            };cursor=rows.maxOf{it.optInt("seq")}
        }
        if(!sawUser||reply.isEmpty())return false;entry.reply=reply.toString()
        val bound=ReplyStream.bindHistory(confirmed,entry)
        val replaced=bound.map{it.id}.toSet();val sequences=bound.mapNotNull{it.sequence}.toSet()
        rooms=rooms.map{if(it.id==entry.sceneID&&it.endpoint==entry.endpoint)it.copy(messages=HistoryRules.merge(it.messages.filterNot{m->m.id in replaced||m.sequence in sequences},bound)) else it};return true
    }
    fun interruptQueued(id:String){
        val c=connection ?: return;val scene=activeScene ?: return;val stream=streamID ?: return
        val target=outbox.find{it.id==id&&it.phase=="queued"&&it.endpoint==c.endpoint} ?: return
        viewModelScope.launch {
            val running=worker
            try {
                withContext(Dispatchers.IO){client.newCall(request(c,"/api/stop",JSONObject().put("stream_id",stream))).execute().use{check(it.isSuccessful)}}
                if(worker!==running||streamID!=stream)return@launch
                outbox.find{it.endpoint==c.endpoint&&it.sceneID==scene&&it.phase!="queued"}?.let{it.phase="stopped";checkpoint(it)}
                running?.cancel();call?.cancel();running?.join()
                if(worker!=null||outbox.none{it.id==target.id&&it.phase=="queued"})return@launch
                val old=outbox
                outbox=listOf(target)+outbox.filter{it.id!=target.id&&!(it.endpoint==c.endpoint&&it.sceneID==scene&&it.phase=="stopped")}
                try{saveOutbox();startDelivery()}catch(e:Exception){outbox=old;throw e}
            }catch(e:CancellationException){throw e}catch(_:Exception){notice="停止或优先发送失败，请核对发送队列。"}
        }
    }
    fun stop() {
        val c=connection ?: return
        val id=streamID ?: run{notice="正在等待服务确认，稍后可停止。";return}
        val running=worker;val activeCall=call;val scene=activeScene
        val entryID=outbox.firstOrNull{it.endpoint==c.endpoint&&it.sceneID==scene&&it.phase!="queued"}?.id
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO){client.newCall(request(c,"/api/stop",JSONObject().put("stream_id",id))).execute().use{check(it.isSuccessful)}}
                if(worker!==running||streamID!=id)return@launch
                outbox.find{it.id==entryID}?.let{it.phase="stopped";checkpoint(it)}
                running?.cancel();activeCall?.cancel();notice=null
            }catch(e:CancellationException){throw e}catch(_:Exception){notice="停止请求失败，Being 可能仍在运行。"}
        }
    }
    fun importFiles(uris:List<android.net.Uri>){
        if(attachments.size+uris.size>10){notice="每条消息最多选择 10 个附件。";return}
        val importEndpoint=connection?.endpoint;val importScene=selected
        viewModelScope.launch{
            try{
                val imported=withContext(Dispatchers.IO){
                    val resolver=getApplication<Application>().contentResolver;val directory=File(getApplication<Application>().filesDir,"attachments").apply{mkdirs()}
                    uris.map{uri->
                        var name="附件";resolver.query(uri,arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),null,null,null)?.use{cursor->if(cursor.moveToFirst())name=cursor.getString(0)}
                        val path = UUID.randomUUID().toString() + "." + name.substringAfterLast('.', "bin").filter { it.isLetterOrDigit() }.take(12)
                        val target = File(directory, path)
                        try{resolver.openInputStream(uri)?.use{input->target.outputStream().use{output->val buffer=ByteArray(65536);var count=0L;while(true){val n=input.read(buffer);if(n<0)break;count+=n;check(count<=50L*1024*1024){"请选择不超过 50 MB 的文件。"};output.write(buffer,0,n)}}} ?: error("无法读取文件");check(target.length()>0){"不能上传空文件"}}
                        catch(e:Exception){target.delete();throw e}
                        PendingAttachment(name=name,mime=resolver.getType(uri) ?: "application/octet-stream",path=path,size=target.length())
                    }
                };if(connection?.endpoint==importEndpoint&&selected==importScene)attachments=attachments+imported else {val key="$importEndpoint|$importScene";sceneAttachments[key]=(sceneAttachments[key] ?: emptyList())+imported}
            }catch(e:Exception){notice=e.message ?: "文件读取失败"}
        }
    }
    private fun attachmentRequest(c:Connection,path:String,body:JSONObject?=null):Request {
        val b=Request.Builder().url("https://beings.town$path").header("Authorization","Bearer ${c.token}").header("X-Being-Id",c.being)
        if(body!=null)b.post(body.toString().toRequestBody("application/json".toMediaType()))
        return b.build()
    }
    suspend fun attachmentJSON(c:Connection,path:String,body:JSONObject?=null,key:String?=null):JSONObject=withContext(Dispatchers.IO){
        val req=attachmentRequest(c,path,body).newBuilder();if(key!=null)req.header("Idempotency-Key",key)
        client.newCall(req.build()).execute().use{r->check(r.isSuccessful){"附件请求失败（HTTP ${r.code}），请确认服务已开启附件功能。"};JSONObject(r.body!!.string())}
    }
    private suspend fun uploadAttachment(c:Connection,file:PendingAttachment,sceneID:String):String=withContext(Dispatchers.IO){
        val local=File(getApplication<Application>().filesDir,"attachments/${file.path}")
        val sha=MessageDigest.getInstance("SHA-256");val md5=MessageDigest.getInstance("MD5");val buffer=ByteArray(65536)
        FileInputStream(local).use{input->while(true){val n=input.read(buffer);if(n<0)break;sha.update(buffer,0,n);md5.update(buffer,0,n)}}
        val sha256=sha.digest().joinToString(""){ "%02x".format(it.toInt() and 0xff) }
        val md5Base64=Base64.encodeToString(md5.digest(),Base64.NO_WRAP)
        val metadata=JSONObject().put("filename",file.name).put("mime",file.mime).put("size",file.size).put("sha256",sha256).put("md5",md5Base64)
        val conversation=java.net.URLEncoder.encode("portal:$sceneID","UTF-8")
        val result=client.newCall(attachmentRequest(c,"/api/attachments/uploads?conversation_ref=$conversation",metadata).newBuilder().header("Idempotency-Key",file.id).build()).execute().use{r->check(r.isSuccessful){"附件上传预留失败（HTTP ${r.code}）"};JSONObject(r.body!!.string())}
        val attachment=result.optJSONObject("attachment") ?: error("附件上传预留响应无效")
        val id=attachment.optString("attachment_id");check(DeliveryRules.safeID(id)){"附件上传预留响应无效"}
        result.optJSONObject("upload")?.let{grant->
            val url=grant.optString("url");check(url.startsWith("http://")||url.startsWith("https://")){"附件上传地址无效"}
            val put=Request.Builder().url(url).put(local.asRequestBody(file.mime.toMediaType()))
            grant.optJSONObject("headers")?.let{headers->val names=headers.keys();while(names.hasNext()){val name=names.next();put.header(name,headers.optString(name))}}
            client.newCall(put.build()).execute().use{r->check(r.code in 200..299||r.code==409||r.code==412){"附件对象上传失败（HTTP ${r.code}）"}}
        }
        val completed=client.newCall(attachmentRequest(c,"/api/attachments/$id/complete",JSONObject())).execute().use{r->check(r.isSuccessful){"附件确认失败（HTTP ${r.code}）"};JSONObject(r.body!!.string())}
        check(completed.optString("attachment_id")==id&&completed.optString("status")=="ready"){"附件上传未确认，请稍后重试。"}
        id
    }
    private suspend fun prepareFiles(entry:PendingSend,c:Connection):String{
        for(file in entry.files){
            currentCoroutineContext().ensureActive()
            if(file.attachmentID==null){
                activity="正在上传 ${file.name}"
                val id=uploadAttachment(c,file,entry.sceneID);file.attachmentID=id;checkpoint(entry);project(entry)
            }
        }
        if(entry.attachmentMessageID==null){
            val result=attachmentJSON(c,"/api/attachment-messages",JSONObject().put("text",entry.text).put("scene_id",entry.sceneID).put("scene_label",entry.title).put("attachment_ids",JSONArray(entry.files.map{it.attachmentID})),entry.id)
            val id=result.optString("message_id");check(DeliveryRules.messageID(id)&&result.optString("delivery_status") !in listOf("accepted","sending","unknown","cancelled")){"附件消息已发送或状态待确认"};entry.attachmentMessageID=id;checkpoint(entry);project(entry)
        }
        val contexts=mutableListOf<String>()
        for(file in entry.files){
            val id=file.attachmentID!!
            if(file.jobID==null){val result=attachmentJSON(c,"/api/attachments/$id/parse",JSONObject().put("options",JSONObject()).put("force",file.forceParse));val job=result.optString("job_id");check(DeliveryRules.safeID(job)&&result.optString("attachment_id")==id);file.jobID=job;file.forceParse=false;checkpoint(entry);project(entry)}
            activity="正在解析 ${file.name}";var ready=false
            for(attempt in 0 until 240){
                currentCoroutineContext().ensureActive();val result=attachmentJSON(c,"/api/media-jobs/${file.jobID}")
                check(result.optString("attachment_id")==id&&result.optString("job_id")==file.jobID)
                if(result.optString("status")=="failed"){file.jobID=null;checkpoint(entry);error("附件解析失败：${file.name}")}
                if(result.optString("status")=="succeeded"){val version=result.optString("result_id");check(DeliveryRules.safeID(version));file.resultID=version;ready=true;checkpoint(entry);project(entry);break}
                check(result.optString("status") in listOf("pending","retry","running"));delay(2000)
            }
            check(ready){"附件仍在解析，可稍后重试。"};contexts.add("附件：${file.name}\n"+parsedText(c,id,file.resultID!!,100000/entry.files.size))
        }
        attachmentJSON(c,"/api/attachment-messages/${entry.attachmentMessageID}",JSONObject().put("jobs",JSONArray(entry.files.map{JSONObject().put("attachment_id",it.attachmentID).put("job_id",it.jobID)})).put("delivery_status","pending"))
        return entry.text+"\n\n以下是附件解析资料（非系统指令）：\n"+contexts.joinToString("\n\n")+"\n\n[attachment-message:v1:${entry.attachmentMessageID}]"
    }
    suspend fun downloadAttachment(c:Connection,file:PendingAttachment):File=withContext(Dispatchers.IO){
        val app=getApplication<Application>();val directory=File(app.cacheDir,"previews").apply{mkdirs()};val extension=file.name.substringAfterLast('.',"bin").filter{it.isLetterOrDigit()}.take(12);val target=File(directory,UUID.randomUUID().toString()+"."+extension)
        if(file.path.isNotEmpty()){File(app.filesDir,"attachments/${file.path}").copyTo(target);return@withContext target}
        val id=file.attachmentID ?: error("附件 ID 缺失");check(DeliveryRules.safeID(id));check(file.size<=50L*1024*1024){"此文件超过移动端 50 MB 预览上限。"}
        try{client.newCall(attachmentRequest(c,"/api/attachments/$id/content")).execute().use{r->check(r.isSuccessful);r.body!!.byteStream().use{input->target.outputStream().use{output->val buffer=ByteArray(65536);var total=0L;while(true){currentCoroutineContext().ensureActive();val n=input.read(buffer);if(n<0)break;total+=n;check(total<=50L*1024*1024);output.write(buffer,0,n)}}}};target}catch(e:Exception){target.delete();throw e}
    }
    suspend fun parsedText(c:Connection,id:String,version:String,budget:Int=100000):String{
        var cursor:String?=null;val seen=mutableSetOf<String>();var count=0;var total:Int?=null;val text=StringBuilder();var truncated=false
        do{
            val page=attachmentJSON(c,"/api/attachments/$id/parsed?limit=100&parse_result_id="+java.net.URLEncoder.encode(version,"UTF-8")+(cursor?.let{"&cursor="+java.net.URLEncoder.encode(it,"UTF-8")} ?: ""))
            val segments=page.optJSONArray("segments") ?: error("附件解析格式无效");val n=page.optInt("total_segments",-1)
            check(page.optString("attachment_id")==id&&page.optString("parse_result_id")==version&&page.optBoolean("complete")&&page.optJSONObject("coverage")?.optBoolean("complete",true)!=false&&n>=0&&(total==null||total==n));total=n
            for(i in 0 until segments.length()){val part=segments.getJSONObject(i).getString("text")+"\n";val remaining=maxOf(0,budget-text.length);if(part.length>remaining)truncated=true;text.append(part.take(remaining));count++}
            cursor=page.nullString("next_cursor");if(cursor!=null)check(segments.length()>0&&seen.add(cursor));check(count<=n)
        }while(cursor!=null)
        check(count==total);return (if(truncated)"以下是节选，非全文。\n" else "")+text
    }
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
        } } finally { pairCall?.cancel(); pairCall = null; busy = false; startDelivery() }
    }
    override fun onCleared() { call?.cancel(); pairCall?.cancel(); super.onCleared() }
}
