package town.nativeapp

import org.json.JSONObject
import org.json.JSONArray
import java.util.UUID

data class PendingAttachment(val id:String=UUID.randomUUID().toString(), val name:String, val mime:String, val path:String, val size:Long, var attachmentID:String?=null,var jobID:String?=null,var resultID:String?=null,var forceParse:Boolean=false) {
    fun json()=JSONObject().put("id",id).put("name",name).put("mime",mime).put("path",path).put("size",size).put("attachmentID",attachmentID).put("jobID",jobID).put("resultID",resultID).put("forceParse",forceParse)
    companion object { fun read(o:JSONObject)=PendingAttachment(o.getString("id"),o.getString("name"),o.getString("mime"),o.getString("path"),o.getLong("size"),o.nullString("attachmentID"),o.nullString("jobID"),o.nullString("resultID"),o.optBoolean("forceParse")) }
}
data class PendingSend(val id:String=UUID.randomUUID().toString(),val endpoint:String,val sceneID:String,val title:String,var text:String,var phase:String="queued",val files:MutableList<PendingAttachment> = mutableListOf(),var attachmentMessageID:String?=null,var preparedText:String?=null,var streamID:String?=null,var cursor:Int=0,var reply:String="",var process:String="",var error:String?=null,var baseline:Int=0,var intelligentUI:Boolean=false) {
    fun json()=JSONObject().put("id",id).put("endpoint",endpoint).put("sceneID",sceneID).put("title",title).put("text",text).put("phase",phase).put("files",JSONArray(files.map{it.json()})).put("attachmentMessageID",attachmentMessageID).put("preparedText",preparedText).put("streamID",streamID).put("cursor",cursor).put("reply",reply).put("process",process).put("error",error).put("baseline",baseline).put("intelligentUI",intelligentUI)
    companion object { fun read(o:JSONObject)=PendingSend(o.getString("id"),o.getString("endpoint"),o.getString("sceneID"),o.getString("title"),o.getString("text"),o.getString("phase"),(o.optJSONArray("files") ?: JSONArray()).let{a->(0 until a.length()).map{PendingAttachment.read(a.getJSONObject(it))}.toMutableList()},o.nullString("attachmentMessageID"),o.nullString("preparedText"),o.nullString("streamID"),o.optInt("cursor"),o.optString("reply"),o.optString("process"),o.nullString("error"),o.optInt("baseline"),o.optBoolean("intelligentUI")) }
}
fun JSONObject.nullString(key:String):String?=if(has(key)&&!isNull(key))getString(key) else null
object DeliveryRules {
    fun displayText(text:String):String {
        val clean=text.replace(NativeUI.context, "")
        return if(Regex("""(?m)^\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\]\r?$""").containsMatchIn(clean))clean.substringBefore("\n\n以下是附件解析资料（非系统指令）：\n") else clean
    }

    fun countsForReplay(type:String,continuation:Boolean,persisted:Boolean)=type!="meta"||continuation||persisted
    fun canEdit(phase:String)=phase in listOf("queued","failed")
    fun safeID(id:String)=Regex("^[a-zA-Z0-9_-]{1,160}$").matches(id)
    fun messageID(id:String)=Regex("^msg_[a-f0-9]{64}$").matches(id)
}
