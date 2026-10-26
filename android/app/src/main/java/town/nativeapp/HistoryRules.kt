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
        .put("id",m.id).put("localBaseline",m.localBaseline).put("replyTo",m.replyTo).put("localAfter",m.localAfter).put("streaming",m.streaming).put("persistedText",m.persistedText)
    fun decodeLocal(m:JSONObject)=Message(m.getString("role"),m.getString("text"),m.optString("scene_id").takeIf{it.isNotEmpty()&&it!="null"},if(m.has("seq")&&!m.isNull("seq"))m.getInt("seq") else null,m.optString("kind").takeIf{it.isNotEmpty()&&it!="null"},m.optString("timestamp").takeIf{it.isNotEmpty()&&it!="null"},m.optString("scene_label").takeIf{it.isNotEmpty()&&it!="null"},m.optJSONArray("files")?.let{a->(0 until a.length()).map{PendingAttachment.read(a.getJSONObject(it))}},m.nullString("process"))
        .copy(id=m.nullString("id") ?: m.nullString("kind")?.takeIf{it.startsWith("local:")} ?: if(m.has("seq")&&!m.isNull("seq"))"server:${m.getInt("seq")}" else java.util.UUID.randomUUID().toString(),
            localBaseline=if(m.has("localBaseline")&&!m.isNull("localBaseline"))m.getInt("localBaseline") else null,replyTo=m.nullString("replyTo"),localAfter=m.nullString("localAfter"),
            streaming=if(m.has("streaming")&&!m.isNull("streaming"))m.getBoolean("streaming") else null,persistedText=m.nullString("persistedText"))

    fun role(raw:String)=if(raw=="user")"user" else "being"
    fun text(value:Any?):String=when(value){is String->value;is JSONArray->(0 until value.length()).mapNotNull{val item=value.optJSONObject(it);(item?.opt("text") ?: item?.opt("content")) as? String}.joinToString("\n\n");else->""}
    fun marker(text:String)=when{ text.startsWith("[breath yielded",true)->"放下手头的事，转向你";text.startsWith("[breath interrupted",true)->"已停止";text.startsWith("[breath superseded",true)->"被新的对话取代";else->text.trim('[',']') }
    fun decode(r:JSONObject):Message {
        val content=text(r.opt("content"));val marker=r.optString("from")=="system"||r.optString("type")=="marker"
        return Message(role(r.optString("role")),if(marker)marker(content) else SceneRules.stripTransition(content),r.optString("scene_id").takeIf{it.isNotEmpty()&&it!="null"},if(r.has("seq"))r.optInt("seq") else null,if(marker)"marker" else null,r.optString("at").takeIf{it.isNotEmpty()},r.optString("scene_label",r.optJSONObject("scene_meta")?.optString("scene_label") ?: "").takeIf{it.isNotEmpty()})
            .let { if(it.sequence!=null)it.copy(id="server:${it.sequence}") else it }
    }

    fun merge(local:List<Message>,confirmed:List<Message>,activeIDs:Set<String> = emptySet()):List<Message> {
        val indexed=linkedMapOf<Int,Message>()
        local.forEach{m->m.sequence?.let{indexed[it]=m}}
        fun bind(remote:Message,old:Message):Message = remote.copy(
            id=old.id,kind=if(remote.kind=="marker")remote.kind else old.kind ?: remote.kind,
            files=remote.files ?: old.files,process=remote.process ?: old.process,
            replyTo=old.replyTo ?: remote.replyTo,localAfter=old.localAfter ?: remote.localAfter,localBaseline=old.localBaseline ?: remote.localBaseline,
            text=if(old.streaming==true&&remote.streaming!=false)old.text else remote.text,
            persistedText=if(old.streaming==true&&remote.streaming!=false)remote.text else remote.persistedText,
            streaming=if(old.streaming==true&&remote.streaming!=false)true else remote.streaming
        )
        confirmed.forEach { row -> row.sequence?.let { seq -> indexed[seq]=indexed[seq]?.let{bind(row,it)} ?: row } }
        val known=local.mapNotNull{it.sequence}.toSet()
        val echoes=confirmed.filter{it.sequence!=null&&it.sequence !in known}.sortedBy{it.sequence}.toMutableList()
        val localByID=local.associateBy{it.id}
        fun promptStart(message:Message):Int? {
            val prompt=localByID[message.replyTo] ?: return null
            val baseline=message.localBaseline ?: return null
            val prompts=confirmed.filter{it.role=="user"&&it.sceneID==prompt.sceneID&&(it.sequence ?: 0)>baseline&&DeliveryRules.matchesSubmittedText(it.text,prompt.text)}
            return prompt.sequence ?: prompts.singleOrNull()?.sequence
        }
        fun liveEcho(message:Message):Message? {
            val start=promptStart(message) ?: return null
            val end=indexed.values.filter{it.role=="user"&&it.sceneID==message.sceneID&&(it.sequence ?: 0)>start}.mapNotNull{it.sequence}.minOrNull() ?: Int.MAX_VALUE
            val previous=localByID[message.localAfter]?.sequence ?: start
            val candidates=indexed.values.filter{remote->remote.role=="being"&&remote.kind==null&&remote.sceneID==message.sceneID&&
                (remote.sequence ?: 0)>maxOf(start,previous)&&(remote.sequence ?: 0)<end&&(remote.replyTo==null||remote.id==message.id)&&
                message.text.isNotEmpty()&&remote.text.isNotEmpty()&&(remote.text==message.text||message.streaming==true&&(remote.text.startsWith(message.text)||message.text.startsWith(remote.text)))}
            val candidate=candidates.singleOrNull() ?: return null
            val competing=local.count{it.sequence==null&&it.replyTo==message.replyTo&&it.text.isNotEmpty()&&
                (candidate.text==it.text||it.streaming==true&&(candidate.text.startsWith(it.text)||it.text.startsWith(candidate.text)))}
            return candidate.takeIf{competing==1}
        }
        val pending=local.filter { row ->
            if(row.sequence!=null||(role(row.role)=="being"&&row.text.isBlank()))false else {
                val live=liveEcho(row)
                if(live!=null) {
                    indexed[live.sequence!!]=bind(live,row)
                    echoes.removeAll{it.sequence==live.sequence}
                    return@filter false
                }
                if(promptStart(row)!=null)return@filter true
                val match=echoes.indexOfFirst { remote ->
                    role(remote.role)==role(row.role)&&remote.sceneID==row.sceneID&&
                        (row.localBaseline==null||remote.sequence!!>row.localBaseline)&&DeliveryRules.matchesSubmittedText(remote.text,row.text)
                }
                if(match>=0) {
                    val remote=echoes.removeAt(match)
                    indexed[remote.sequence!!]=bind(remote,row)
                    false
                } else if(row.role=="being"&&row.timestamp==null&&row.localBaseline==null&&row.id !in activeIDs) {
                    // Migrate only a unique, substantial final suffix from older clients.
                    val matches=indexed.values.filter { remote -> remote.sceneID==row.sceneID&&remote.role=="being"&&remote.kind==null&&
                        remote.text.length>=256&&row.text.length>remote.text.length&&remote.text.length*2>=row.text.length&&row.text.endsWith(remote.text) }
                    if(matches.size==1) {
                        val remote=matches.single()
                        indexed[remote.sequence!!]=remote.copy(process=listOfNotNull(remote.process,row.process,row.text.dropLast(remote.text.length).trim()).filter{it.isNotEmpty()}.joinToString("\n\n"))
                        false
                    } else true
                } else true
            }
        }
        return ordered(indexed.values.toList()+pending)
    }

    fun ordered(messages:List<Message>):List<Message> {
        val parents=messages.associateBy{it.id}
        val repliesByPrompt=messages.filter{it.role=="being"&&it.replyTo!=null}.groupBy{it.replyTo}
        val positions=mutableMapOf<String,Pair<Int,Int>>()
        fun position(message:Message,visiting:Set<String> = emptySet()):Pair<Int,Int> {
            positions[message.id]?.let{return it}
            message.sequence?.let{return it to 0}
            val baseline=message.localBaseline ?: Int.MAX_VALUE
            val parent=parents[message.localAfter ?: message.replyTo]
            if(message.id in visiting||parent==null||parent.sceneID!=message.sceneID)return baseline to 1
            // A question queued during thinking must follow the entire preceding
            // turn, including bubbles that did not exist when it was queued.
            val predecessors=if(message.role=="user") {
                val promptID=if(parent.role=="user")parent.id else parent.replyTo
                listOf(parent)+repliesByPrompt[promptID].orEmpty().filter{it.sceneID==message.sceneID}
            } else listOf(parent)
            val preceding=predecessors.map{position(it,visiting+message.id)}
                .maxWith(compareBy<Pair<Int,Int>>{it.first}.thenBy{it.second})
            return (maxOf(baseline,preceding.first) to if(preceding.first>=baseline)preceding.second+1 else 1).also{positions[message.id]=it}
        }
        messages.forEach{positions[it.id]=position(it)}
        return messages.withIndex().sortedWith(compareBy<IndexedValue<Message>>{positions.getValue(it.value.id).first}
            .thenBy{positions.getValue(it.value.id).second}.thenBy{if(it.value.sequence!=null)0 else 1}
            .thenBy{it.value.timestamp.orEmpty()}.thenBy{it.index}).map{it.value}
    }
}
