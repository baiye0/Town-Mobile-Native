package town.nativeapp
import org.json.JSONArray
import org.json.JSONObject
object HistoryRules {
    fun sbsStatus(snapshot:JSONObject):String? {
        if(snapshot.opt("stream_id") !is String || snapshot.opt("finished") !is Boolean)return null
        val origin=snapshot.optString("origin")
        if(snapshot.getBoolean("finished") || origin.isEmpty() || origin=="human" || !snapshot.nullString("scene_id").isNullOrEmpty())return ""
        var phase=if(origin=="callback")"正在执行回调" else "正在思考"
        val events=snapshot.optJSONArray("events") ?: JSONArray()
        for(i in 0 until events.length()) {
            val event=events.optJSONObject(i) ?: continue
            val type=event.optString("event");val data=event.optJSONObject("data") ?: JSONObject();val delta=data.optJSONObject("delta") ?: JSONObject()
            when {
                type=="tool_use" || data.optJSONObject("content_block")?.optString("type")=="tool_use" -> phase="正在执行工具"
                type in listOf("thinking","reasoning","tool_result") || delta.optString("type")=="thinking_delta" -> phase="正在思考"
                type in listOf("text","message") || delta.opt("text") is String -> phase="正在整理回复"
            }
        }
        return (if(origin=="callback")"SBS 回调 · " else "SBS 活动 · ")+phase
    }

    fun requestPath(cursor:Int)=if(cursor>0) "/api/history?limit=500&after=$cursor" else "/api/history?limit=500"
    fun failureMessage(error:Exception):String {
        val detail=when {
            error is java.net.SocketTimeoutException -> "请求超时，请重试。"
            error is java.io.IOException -> "网络连接失败，请联网后重试。"
            error.message in listOf("HTTP 401","HTTP 403") -> "连接凭据失效或无权限，请重新连接。"
            error.message?.matches(Regex("HTTP [0-9]{3}")) == true -> "服务返回 ${error.message}，请稍后重试。"
            else -> "服务返回的数据格式不正确，请重试。"
        }
        return "历史记录读取失败：$detail"
    }

    fun encodeLocal(m:Message)=JSONObject().put("role",m.role).put("text",m.text).put("scene_id",m.sceneID).put("seq",m.sequence).put("kind",m.kind).put("timestamp",m.timestamp).put("scene_label",m.sceneLabel).put("files",m.files?.let{JSONArray(it.map{f->f.json()})}).put("process",m.process)
    fun decodeLocal(m:JSONObject)=Message(m.getString("role"),m.getString("text"),m.optString("scene_id").takeIf{it.isNotEmpty()&&it!="null"},if(m.has("seq")&&!m.isNull("seq"))m.getInt("seq") else null,m.optString("kind").takeIf{it.isNotEmpty()&&it!="null"},m.optString("timestamp").takeIf{it.isNotEmpty()&&it!="null"},m.optString("scene_label").takeIf{it.isNotEmpty()&&it!="null"},m.optJSONArray("files")?.let{a->(0 until a.length()).map{PendingAttachment.read(a.getJSONObject(it))}},m.nullString("process"))

    fun role(raw:String)=if(raw=="user")"user" else "being"
    fun text(value:Any?):String=when(value){is String->value;is JSONArray->(0 until value.length()).mapNotNull{val item=value.optJSONObject(it);(item?.opt("text") ?: item?.opt("content")) as? String}.joinToString("\n\n");else->""}
    fun marker(text:String)=when{ text.startsWith("[breath yielded",true)->"放下手头的事，转向你";text.startsWith("[breath interrupted",true)->"已停止";text.startsWith("[breath superseded",true)->"被新的对话取代";else->text.trim('[',']') }
    fun decode(r:JSONObject):Message{val content=text(r.opt("content"));val marker=r.optString("from")=="system"||r.optString("type")=="marker";return Message(role(r.optString("role")),if(marker)marker(content) else SceneRules.stripTransition(content),r.optString("scene_id").takeIf{it.isNotEmpty()&&it!="null"},if(r.has("seq"))r.optInt("seq") else null,if(marker)"marker" else null,r.optString("at").takeIf{it.isNotEmpty()},r.optString("scene_label",r.optJSONObject("scene_meta")?.optString("scene_label") ?: "").takeIf{it.isNotEmpty()})}
    fun merge(local:List<Message>,confirmed:List<Message>):List<Message>{
        val indexed=linkedMapOf<Int,Message>();local.forEach{m->m.sequence?.let{indexed[it]=m}};confirmed.forEach{m->m.sequence?.let{seq->indexed[seq]=m.copy(files=m.files ?: indexed[seq]?.files,process=m.process ?: indexed[seq]?.process)}}
        val known=local.mapNotNull{it.sequence}.toSet();val echoes=confirmed.filter{it.sequence!=null&&it.sequence !in known}.toMutableList()
        val attachmentMarker=Regex("(?m)^\\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\\]\\r?$")
        fun attachmentLine(text:String)=text.lineSequence().lastOrNull{it.startsWith("[attachment-message:v1:")}
        val pending=local.filter{m->if(m.sequence!=null || (role(m.role)=="being" && m.text.isBlank()))false else {val hasAttachment=attachmentMarker.containsMatchIn(m.text);val candidates=if(hasAttachment)confirmed else echoes;val index=candidates.indexOfLast{row->role(row.role)==role(m.role)&&row.sceneID==m.sceneID&&(if(hasAttachment)attachmentLine(row.text)==attachmentLine(m.text) else row.text==SceneRules.stripTransition(m.text))};if(index>=0){candidates[index].sequence?.let{seq->indexed[seq]=indexed[seq]!!.copy(files=m.files,process=m.process)};if(!hasAttachment)echoes.removeAt(index);false}else true}}
        return indexed.values.sortedBy{it.sequence}+pending
    }
}
