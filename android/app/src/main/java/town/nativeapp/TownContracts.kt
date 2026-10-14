package town.nativeapp
import org.json.JSONObject
class PairCodeCollector(private val sceneID:String){
    private var reply=""
    fun consume(event:SSEEvent):String?{
        if(event.data=="[DONE]")return finish()
        val data=JSONObject(event.data)
        if(data.has("scene_id")&&!data.isNull("scene_id")&&data.optString("scene_id")!=sceneID)return null
        val type=if(event.name=="message")data.optString("type","message") else event.name
        check(type!="error"){"Being 未能完成配对请求，请使用手动配对。"}
        if(type in listOf("done","end"))return finish()
        if(type=="content_block_delta")data.optJSONObject("delta")?.let{delta->if(!delta.has("type")||delta.optString("type")=="text_delta")reply+=delta.optString("text","")}
        else if(type in listOf("text","message"))reply+=data.optString("text",data.optString("content",""))
        check(reply.length<=8192){"Being 未返回明确的配对码，请使用手动配对。"}
        if(type=="message_stop"){val code=finish();reply="";return code}
        return null
    }
    fun finish():String? {
        val codes=Regex("(?<![A-Za-z0-9])[A-Z0-9]{6}(?![A-Za-z0-9])").findAll(reply).map{it.value}.toSet()
        check(codes.size<=1){"未收到唯一的 6 位配对码，请使用手动配对。"};return codes.firstOrNull()
    }
}
object TownContracts{
    fun identity(raw:String):String{val value=raw.trim();val id=if(value.startsWith("t_"))value else value.lowercase();require(Regex("^(t_[A-Za-z0-9_-]{1,62}|[a-z0-9_-]{1,64})$").matches(id));return id}
    fun validatePair(input:String,townID:String?,beingID:String?,token:String){
        require(Regex("^[A-Za-z0-9._~-]{16,2048}$").matches(token))
        if(townID!=null)require(identity(townID)==townID&&townID.startsWith("t_"))
        if(input.startsWith("t_"))require(townID?.startsWith(input)==true) else if(beingID!=null)require(beingID==input)
    }
}
