package town.nativeapp
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject

class DeliveryTest {
    @Test fun checkpointRestoresReplyAndCursorWithoutAuthorizingResend(){
        val entry=PendingSend(endpoint="https://example.com/being",sceneID="scene-a",title="A",text="hello",phase="sending",streamID="stream-1",cursor=37,reply="已收到的中文",process="read file",files=mutableListOf(PendingAttachment(name="报告.pdf",mime="application/pdf",path="local.pdf",size=42,attachmentID="a_1",jobID="j_1",resultID="r_1")))
        val restored=PendingSend.read(JSONObject(entry.json().toString()))
        assertEquals(entry.id,restored.id);assertEquals(37,restored.cursor);assertEquals(entry.reply,restored.reply);assertEquals("r_1",restored.files[0].resultID);assertFalse(DeliveryRules.canEdit(restored.phase));assertFalse(DeliveryRules.canEdit("unknown"))
    }
    @Test fun cursorIncludesPersistenceAndContinuationMeta(){
        assertFalse(DeliveryRules.countsForReplay("meta",false,false));assertTrue(DeliveryRules.countsForReplay("meta",true,false));assertTrue(DeliveryRules.countsForReplay("meta",false,true));assertTrue(DeliveryRules.countsForReplay("tool_use",false,false))
    }
    @Test fun historyKeepsLocalAttachmentAndToolProcess(){
        val local=listOf(Message("user","file","s",files=listOf(PendingAttachment(name="a.pdf",mime="application/pdf",path="a.pdf",size=12))),Message("being","answer","s",process="read file"))
        val confirmed=listOf(Message("user","file","s",1),Message("being","answer","s",2))
        val merged=HistoryRules.merge(local,confirmed);assertEquals(2,merged.size);assertEquals("a.pdf",merged[0].files!![0].name);assertEquals("read file",merged[1].process);assertEquals("read file",HistoryRules.merge(merged,confirmed)[1].process)
        assertEquals("read file",HistoryRules.decodeLocal(HistoryRules.encodeLocal(merged[1])).process)
    }
    @Test fun relationFiltersDoNotConfuseSimilarIDs(){
        val filter=FeedFilter(relation="mentions")
        assertFalse(filter.matches(JSONObject().put("content","hello @alice_work"),"alice"));assertTrue(filter.matches(JSONObject().put("content","hello @alice"),"alice"))
        assertTrue(FeedFilter(relation="about").matches(JSONObject().put("recipient_town_id","t_A"),"t_A"));assertFalse(FeedFilter(relation="about").matches(JSONObject().put("recipient_town_id","t_a"),"t_A"))
        assertFalse(FeedFilter(days=1).matches(JSONObject().put("at","invalid"),"alice"))
    }
    @Test fun nativeUIAssemblesAndRejectsCycles(){
        val source="""{"op":"begin","version":2,"title":"Example"}
{"op":"state","key":"n","initial":2}
{"op":"node","node":{"id":"root","type":"stack"}}
{"op":"node","parent":"root","node":{"id":"quantity","type":"stepper","bind":"n","min":1,"max":10}}
{"op":"commit"}"""
        assertEquals(1,NativeUI.decode(source).getJSONArray("body").getJSONObject(0).getJSONArray("children").length())
        assertTrue(runCatching{NativeUI.decode(source.replace("{\"op\":\"commit\"}",""))}.isFailure)
        val cycle="""{"op":"begin","version":2,"title":"bad"}
{"op":"node","parent":"b","node":{"id":"a","type":"stack"}}
{"op":"node","parent":"a","node":{"id":"b","type":"stack"}}
{"op":"commit"}"""
        assertTrue(runCatching{NativeUI.decode(cycle)}.isFailure)
    }
    @Test fun nativeUIRejectsCodeAndInvalidRanges(){
        for(body in listOf("""{"id":"a","type":"app","code":"fetch('https://example.com')"}""","""{"id":"a","type":"slider","bind":"n","min":10,"max":1}"""))assertTrue(runCatching{NativeUI.decode("""{"version":1,"title":"x","state":{"n":1},"body":[$body]}""")}.isFailure)
        assertEquals(36.0,NativeUI.evaluate(JSONObject("""{"op":"mul","args":[{"state":"n"},12]}"""),mapOf("n" to 3)))
        assertEquals("不支持的表达式",NativeUI.evaluate(JSONObject("""{"op":"eval","args":["1+1"]}"""),emptyMap()))
    }
}
