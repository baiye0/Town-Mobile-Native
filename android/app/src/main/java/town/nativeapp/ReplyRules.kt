package town.nativeapp
import org.json.JSONObject
object ReplyRules {
    private fun value(row:JSONObject,vararg keys:String)=keys.firstNotNullOfOrNull{row.opt(it)?.takeUnless{it==JSONObject.NULL}?.toString()?.takeIf{it.isNotEmpty()}} ?: ""
    fun context(row:JSONObject,rows:List<JSONObject> = emptyList()):String?{
        val id=value(row,"reply_to");if(id.isEmpty())return null
        val author=value(row,"reply_to_display","reply_to_sender_display","reply_to_being","reply_to_sender").takeUnless{it.startsWith("t_")||it.isEmpty()} ?: "原消息"
        val parent=rows.find{value(it,"seq","id","message_id")==id}
        val body=value(row,"reply_to_preview").ifEmpty{parent?.let{value(it,"content","message")} ?: ""}.take(500).ifEmpty{"原消息预览不可用"}
        return "$author：$body"
    }
    fun prompt(place:String,author:String?,content:String,context:String?,description:String):String{
        fun quote(s:String)=s.take(32000).lines().joinToString("\n"){"> $it"}
        val parts=mutableListOf<String>();val request=description.trim()
        if(author!=null){parts.addAll(listOf("请帮我拟一段回复，直接发送，并将回复正文发给我。","位置：$place","回复对象：$author"));if(!context.isNullOrEmpty())parts.add("这条消息所回复的上文：\n"+quote(context));parts.add("要回复的原消息：\n"+quote(content.trim()));if(request.isNotEmpty())parts.add("我已经手写的内容或要求，请结合它完善回复：\n"+quote(request))}
        else parts.addAll(listOf("请根据我的描述和场景位置，帮我写一句适合发布的内容，直接发送，并将发送正文发给我。","场景位置：$place","我的描述：\n"+quote(request)))
        return parts.joinToString("\n\n").take(33000)
    }
}
