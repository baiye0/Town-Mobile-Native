package town.nativeapp
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject
class HistoryPresentationTest {
    @Test fun sbsStatusSeparatesHumanAndFinishedStreams() {
        assertNull(HistoryRules.sbsStatus(JSONObject()))
        assertEquals("",HistoryRules.sbsStatus(JSONObject("""{"stream_id":"a","finished":false,"origin":"human"}""")))
        assertEquals("",HistoryRules.sbsStatus(JSONObject("""{"stream_id":"a","finished":true,"origin":"sbs"}""")))
        assertEquals("",HistoryRules.sbsStatus(JSONObject("""{"stream_id":"a","finished":false,"origin":"sbs","scene_id":"chat"}""")))
        assertEquals("SBS 回调 · 正在执行工具",HistoryRules.sbsStatus(JSONObject("""{"stream_id":"a","finished":false,"origin":"callback","events":[{"event":"tool_use","data":{}}]}""")))
    }

    @Test fun recentHistoryAndSafeFailureDetails() {
        assertEquals("/api/history?limit=500",HistoryRules.requestPath(0))
        assertEquals("/api/history?limit=500&after=501",HistoryRules.requestPath(501))
        assertTrue(HistoryRules.failureMessage(java.net.SocketTimeoutException()).contains("超时"))
        assertTrue(HistoryRules.failureMessage(IllegalStateException("HTTP 401")).contains("凭据"))
        assertTrue(HistoryRules.failureMessage(IllegalStateException("HTTP 503")).contains("HTTP 503"))
        assertFalse(HistoryRules.failureMessage(IllegalStateException("secret-token")).contains("secret-token"))
    }

    @Test fun localCachePreservesPresentationMetadata() {
        val message=Message("being","已停止","scene",7,"marker","2026-10-14T10:30:00Z","主对话")
        assertEquals(message,HistoryRules.decodeLocal(HistoryRules.encodeLocal(message)))
        assertEquals(Message("being","partial"),HistoryRules.decodeLocal(JSONObject("""{"role":"being","text":"partial"}""")))
    }

    @Test fun dropsEmptyReplyPlaceholdersWithoutDroppingPartialText() {
        val pending=listOf(Message("being","","a"),Message("being","partial","a"))
        assertEquals(listOf("reply","partial"),HistoryRules.merge(pending,listOf(Message("being","reply","a",1))).map{it.text})
        assertEquals(listOf("partial"),HistoryRules.merge(pending,emptyList()).map{it.text})
    }

    @Test fun preservesPartialHistoryAndLocalEchoes(){
        val old=Message("being","older","a",1);val pending=Message("user","again","a");val incoming=Message("user","again","a",2)
        val result=HistoryRules.merge(listOf(old,pending,pending),listOf(incoming))
        assertEquals(listOf("older","again","again"),result.map{it.text});assertNull(result.last().sequence)
        assertEquals(2,HistoryRules.merge(listOf(pending.copy(sceneID="b")),listOf(incoming)).size)
    }
    @Test fun keepsServerRolesMarkersAndUnscopedContent(){
        val message=HistoryRules.decode(JSONObject("""{"role":"self","content":"reply","seq":1}"""));assertEquals("being",message.role);assertNull(message.sceneID)
        val marker=HistoryRules.decode(JSONObject("""{"from":"system","content":"[breath interrupted]","seq":2}"""));assertEquals("marker",marker.kind);assertEquals("已停止",marker.text)
    }
    @Test fun markdownRetainsFencedCodeTablesAndLists(){
        val blocks=MarkdownBlocks.parse("# 标题\n\n```swift\nlet x = 1\n```\n\n| 名称 | 内容 |\n| --- | --- |\n| A | `a|b` |\n\n- [x] 完成")
        assertEquals(listOf("heading","code","table","list"),blocks.map{it.kind});assertEquals("`a|b`",blocks[2].rows[1][1]);assertEquals("☑",blocks.last().label)
    }
}
