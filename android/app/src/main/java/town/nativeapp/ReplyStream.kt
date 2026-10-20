package town.nativeapp

import org.json.JSONObject
import java.util.UUID

data class StreamReply(val id:String,val text:String="",val sequence:Int?=null,val closed:Boolean=false,val interim:Boolean=false,val paragraphBreak:Boolean=false) {
    fun json()=JSONObject().put("id",id).put("text",text).put("sequence",sequence).put("closed",closed).put("interim",interim).put("paragraphBreak",paragraphBreak)
    companion object {
        fun read(o:JSONObject)=StreamReply(o.getString("id"),o.optString("text"),if(o.has("sequence")&&!o.isNull("sequence"))o.getInt("sequence") else null,o.optBoolean("closed"),o.optBoolean("interim"),o.optBoolean("paragraphBreak"))
    }
}

/** Mirrors iOS ReplyStream: message_stop closes a bubble, transport completion closes the turn. */
object ReplyStream {
    fun payload(event:SSEEvent):JSONObject? = runCatching { JSONObject(event.data) }.getOrNull()

    fun reasoningText(value:JSONObject):String {
        val delta=value.optJSONObject("delta")
        return (value.opt("text") as? String) ?: (value.opt("content") as? String) ?: (delta?.opt("text") as? String)
            ?: (delta?.opt("thinking") as? String) ?: (value.opt("delta") as? String) ?: ""
    }

    fun consume(type:String,value:JSONObject,entry:PendingSend) {
        val bubbles=(entry.bubbles ?: if(entry.reply.isEmpty())emptyList() else listOf(StreamReply(entry.replyID,entry.reply))).toMutableList()
        val delta=value.optJSONObject("delta")
        val text=when(type){
            "content_block_delta"->delta?.opt("text") as? String
            "text","message"->(value.opt("text") ?: value.opt("content")) as? String
            else->null
        }
        if(!text.isNullOrEmpty()) {
            if(bubbles.isEmpty()||bubbles.last().closed)bubbles.add(StreamReply(if(bubbles.isEmpty())entry.replyID else "local:${entry.id}:reply:${UUID.randomUUID()}"))
            val last=bubbles.last()
            bubbles[bubbles.lastIndex]=last.copy(text=last.text+(if(last.paragraphBreak&&last.text.isNotEmpty())"\n\n" else "")+text,paragraphBreak=false,interim=false)
        } else if(bubbles.isNotEmpty()) {
            val last=bubbles.last()
            bubbles[bubbles.lastIndex]=when(type){
                "tool_use"->last.copy(paragraphBreak=true,interim=true)
                "thinking","reasoning"->if(reasoningText(value).isNotBlank())last.copy(paragraphBreak=true,interim=true) else last
                "content_block_delta"->if((delta?.opt("thinking") as? String).isNullOrEmpty())last else last.copy(paragraphBreak=true,interim=true)
                "message_stop"->last.copy(closed=true)
                "meta"->{
                    val persisted=value.optJSONObject("persisted")
                    val seq=persisted?.optInt("seq") ?: 0
                    val stream=persisted?.optString("stream_id").orEmpty()
                    val from=persisted?.optString("from")
                    if(persisted?.optString("kind")=="self"&&seq>0&&stream.isNotEmpty()&&(entry.streamID==null||entry.streamID==stream)&&from in listOf("final","partial","act_talk")&&bubbles.none{it.sequence==seq})
                        last.copy(sequence=seq,interim=last.interim||from!="final",closed=last.closed||from!="final") else last
                }
                else->last
            }
        }
        entry.bubbles=bubbles
        entry.reply=bubbles.joinToString("\n\n"){it.text}
    }

    fun finish(entry:PendingSend) { entry.bubbles=entry.bubbles?.mapIndexed { i,b -> if(i==entry.bubbles!!.lastIndex)b.copy(closed=true) else b } }
    fun hasFinalReply(entry:PendingSend)=entry.bubbles?.lastOrNull()?.let{it.text.isNotEmpty()&&!it.interim} ?: (entry.bubbles==null&&entry.reply.isNotEmpty())
    fun isProgress(type:String,value:JSONObject,scene:String):Boolean {
        if(value.has("scene_id")&&value.nullString("scene_id")!=scene)return false
        val delta=value.optJSONObject("delta")
        return when(type){
            "tool_use","tool_result"->true
            "content_block_delta"->!((delta?.opt("text") ?: delta?.opt("thinking")) as? String).isNullOrEmpty()
            "thinking","reasoning"->reasoningText(value).isNotEmpty()
            "text","message"->!((value.opt("text") ?: value.opt("content")) as? String).isNullOrEmpty()
            else->false
        }
    }

    fun messages(entry:PendingSend):List<Message> {
        val bubbles=entry.bubbles ?: if(entry.reply.isEmpty())emptyList() else listOf(StreamReply(entry.replyID,entry.reply))
        return bubbles.mapIndexed { index,b ->
            Message("being",b.text,entry.sceneID,sequence=b.sequence,kind=b.id,timestamp=entry.createdAt,id=b.id,
                localBaseline=entry.baseline,replyTo=entry.userID,localAfter=if(index==0)entry.userID else bubbles[index-1].id,streaming=!b.closed)
        }
    }

    fun project(existing:List<Message>,entry:PendingSend):List<Message> {
        val result=existing.toMutableList()
        val rows=listOf(Message("user",entry.preparedText ?: entry.text,entry.sceneID,kind=entry.userID,timestamp=entry.createdAt,
            files=entry.files.toList(),process=entry.process,id=entry.userID,localBaseline=entry.baseline,localAfter=entry.afterID))+messages(entry)
        for(row in rows) {
            val i=result.indexOfFirst{it.id==row.id || it.kind==row.id}
            if(i<0)result.add(row) else {
                val old=result[i]
                if(old.sequence==null||old.sequence==row.sequence||old.streaming==true) {
                    val authoritative=old.persistedText.takeUnless{row.sequence==null&&row.text!=old.text}
                    result[i]=row.copy(sequence=row.sequence ?: old.sequence,persistedText=authoritative,
                        text=if(row.streaming==false)authoritative ?: row.text else row.text)
                } else if(row.role=="user")result[i]=old.copy(process=row.process)
            }
            if(row.sequence!=null) {
                val duplicate=result.indexOfFirst{it.sequence==row.sequence&&it.id!=row.id}
                val live=result.indexOfFirst{it.id==row.id}
                if(duplicate>=0&&live>=0) {
                    val confirmed=result[duplicate]
                    result[live]=row.copy(text=if(row.streaming==true)row.text else confirmed.text,
                        persistedText=if(row.streaming==true)confirmed.text else null)
                    result.removeAt(duplicate)
                }
            }
        }
        return HistoryRules.ordered(result)
    }

    fun bindHistory(confirmed:List<Message>,entry:PendingSend):List<Message> {
        val replies=messages(entry)
        val used=mutableSetOf<String>()
        return confirmed.mapIndexed { index,row ->
            if(row.role=="user")row.copy(id=entry.userID,kind=entry.userID,process=entry.process,localBaseline=entry.baseline,localAfter=entry.afterID)
            else {
                val available=replies.filter{it.id !in used}
                val match=available.firstOrNull{it.sequence!=null&&it.sequence==row.sequence}
                    ?: available.firstOrNull{it.sequence==null&&it.text==row.text}
                    ?: if(index==confirmed.lastIndex)available.lastOrNull{it.sequence==null} else null
                match?.let{used.add(it.id)}
                row.copy(id=match?.id ?: row.id,kind=match?.kind ?: row.kind,streaming=false,replyTo=entry.userID,process=null)
            }
        }
    }
}
