package town.nativeapp
import org.json.JSONArray
import org.json.JSONObject
object HistoryRules {
    fun encodeLocal(m:Message)=JSONObject().put("role",m.role).put("text",m.text).put("scene_id",m.sceneID).put("seq",m.sequence).put("kind",m.kind).put("timestamp",m.timestamp).put("scene_label",m.sceneLabel)
    fun decodeLocal(m:JSONObject)=Message(m.getString("role"),m.getString("text"),m.optString("scene_id").takeIf{it.isNotEmpty()&&it!="null"},if(m.has("seq")&&!m.isNull("seq"))m.getInt("seq") else null,m.optString("kind").takeIf{it.isNotEmpty()&&it!="null"},m.optString("timestamp").takeIf{it.isNotEmpty()&&it!="null"},m.optString("scene_label").takeIf{it.isNotEmpty()&&it!="null"})

    fun role(raw:String)=if(raw=="user")"user" else "being"
    fun text(value:Any?):String=when(value){is String->value;is JSONArray->(0 until value.length()).mapNotNull{val item=value.optJSONObject(it);(item?.opt("text") ?: item?.opt("content")) as? String}.joinToString("\n\n");else->""}
    fun marker(text:String)=when{ text.startsWith("[breath yielded",true)->"放下手头的事，转向你";text.startsWith("[breath interrupted",true)->"已停止";text.startsWith("[breath superseded",true)->"被新的对话取代";else->text.trim('[',']') }
    fun decode(r:JSONObject):Message{val content=text(r.opt("content"));val marker=r.optString("from")=="system"||r.optString("type")=="marker";return Message(role(r.optString("role")),if(marker)marker(content) else SceneRules.stripTransition(content),r.optString("scene_id").takeIf{it.isNotEmpty()&&it!="null"},if(r.has("seq"))r.optInt("seq") else null,if(marker)"marker" else null,r.optString("at").takeIf{it.isNotEmpty()},r.optString("scene_label",r.optJSONObject("scene_meta")?.optString("scene_label") ?: "").takeIf{it.isNotEmpty()})}
    fun merge(local:List<Message>,confirmed:List<Message>):List<Message>{
        val indexed=linkedMapOf<Int,Message>();local.forEach{m->m.sequence?.let{indexed[it]=m}};confirmed.forEach{m->m.sequence?.let{indexed[it]=m}}
        val known=local.mapNotNull{it.sequence}.toSet();val echoes=confirmed.filter{it.sequence!=null&&it.sequence !in known}.toMutableList()
        val pending=local.filter{m->if(m.sequence!=null || (role(m.role)=="being" && m.text.isBlank()))false else {val index=echoes.indexOfFirst{role(it.role)==role(m.role)&&it.text==SceneRules.stripTransition(m.text)&&it.sceneID==m.sceneID};if(index>=0){echoes.removeAt(index);false}else true}}
        return indexed.values.sortedBy{it.sequence}+pending
    }
}
