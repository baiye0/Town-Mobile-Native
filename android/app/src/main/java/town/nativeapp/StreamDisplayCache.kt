package town.nativeapp

/** Reuse history ordering while only text/process changes on existing rows. */
internal class StreamDisplayCache {
    private var key:Any?=null
    private var local:List<Message> = emptyList()
    private var history:List<Message> = emptyList()
    private var active:Set<String> = emptySet()
    private var displayed:List<Message> = emptyList()
    fun render(nextKey:Any,next:List<Message>,confirmed:List<Message>,activeIDs:Set<String>,build:()->List<Message>):List<Message> {
        val updates=mutableMapOf<String,Message>()
        val patch=key==nextKey&&history===confirmed&&active==activeIDs&&local.size==next.size&&local.indices.all { i ->
            val a=local[i];val b=next[i]
            if(a==b)true else {
                updates[b.id]=b
                a.id==b.id&&a.sequence==b.sequence&&a.role==b.role&&a.sceneLabel==b.sceneLabel&&a.persistedText==b.persistedText&&
                    (a.text==b.text||b.streaming==true)&&a.sceneID==b.sceneID&&a.replyTo==b.replyTo&&a.localAfter==b.localAfter&&
                    a.localBaseline==b.localBaseline&&a.timestamp==b.timestamp&&a.kind==b.kind&&a.streaming==b.streaming&&
                    (a.text.isNotBlank()||!a.files.isNullOrEmpty())==(b.text.isNotBlank()||!b.files.isNullOrEmpty())
            }
        }
        displayed=if(patch)displayed.map { row -> updates[row.id]?.let { row.copy(text=it.text,process=it.process,files=it.files,streaming=it.streaming) } ?: row } else build()
        key=nextKey;local=next;history=confirmed;active=activeIDs
        return displayed
    }
}
