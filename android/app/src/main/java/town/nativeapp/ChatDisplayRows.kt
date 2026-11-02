package town.nativeapp

internal data class ChatDisplayRow(val message:Message,val source:Message,val first:Boolean=true,val last:Boolean=true,val segmented:Boolean=false)

/** Split only at completed block boundaries. Never divide a fenced block or a table. */
internal object MarkdownSegments {
    fun split(text:String,target:Int=900):List<String> {
        val parts=mutableListOf<String>()
        var start=0;var cursor=0;var fence:Char?=null;var fenceLength=0
        while(cursor<text.length) {
            val newline=text.indexOf('\n',cursor)
            val end=if(newline<0)text.length else newline+1
            val line=text.substring(cursor,end).trim()
            var closed=false
            if(fence!=null) {
                if(line.length>=fenceLength&&line.all{it==fence}){fence=null;closed=true}
            } else if(line.startsWith("```")||line.startsWith("~~~")) {
                fence=line[0];fenceLength=line.takeWhile{it==fence}.length
            }
            if(fence==null&&(line.isEmpty()||closed)&&end-start>=target&&end<text.length) {
                parts.add(text.substring(start,end));start=end
            }
            cursor=end
        }
        if(start<text.length)parts.add(text.substring(start))
        return parts.ifEmpty{listOf(text)}
    }
}

internal class ChatDisplayRows {
    private var previous=emptyMap<String,List<ChatDisplayRow>>()
    fun render(messages:List<Message>,live:(Message)->Message):List<ChatDisplayRow> {
        val next=linkedMapOf<String,List<ChatDisplayRow>>()
        for(source in messages) {
            val current=if(source.role=="being")live(source) else source
            val old=previous[source.id].orEmpty()
            val eligible=current.role=="being"&&current.kind!="marker"&&current.files.isNullOrEmpty()&&
                !current.text.contains("[attachment-message:")&&!current.text.contains("being.image-generation")&&
                !current.text.contains("intelligent-ui")&&!current.text.contains("![")
            val parts=if(eligible&&current.text.length>900)MarkdownSegments.split(current.text) else emptyList()
            val rows=if(parts.size>1)parts.mapIndexed { index,part ->
                val item=current.copy(id=if(index==0)source.id else "${source.id}:segment:$index",text=part,
                    streaming=current.streaming==true&&index==parts.lastIndex,process=null)
                val row=ChatDisplayRow(item,source,index==0,index==parts.lastIndex,true)
                old.getOrNull(index)?.takeIf{it==row} ?: row
            } else listOf(old.singleOrNull()?.takeIf{!it.segmented&&it.message==source} ?: ChatDisplayRow(source,source))
            next[source.id]=rows
        }
        previous=next
        return next.values.flatten()
    }
}
