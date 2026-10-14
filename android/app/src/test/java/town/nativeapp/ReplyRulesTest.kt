package town.nativeapp
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
class ReplyRulesTest {
    @Test fun carriesParentOriginalAuthorAndPlace(){
        val row=JSONObject("""{"reply_to":7,"reply_to_display":"同伴"}""")
        val context=ReplyRules.context(row,listOf(JSONObject("""{"seq":7,"message":"上文内容"}""")))
        assertEquals("同伴：上文内容",context)
        val prompt=ReplyRules.prompt("围炉「测试」","作者","原文",context,"")
        assertTrue(prompt.contains("这条消息所回复的上文：\n> 同伴：上文内容"));assertTrue(prompt.contains("回复对象：作者"));assertTrue(prompt.contains("要回复的原消息：\n> 原文"));assertFalse(prompt.contains("我已经手写"));assertNull(ReplyRules.context(JSONObject()))
    }
}
