package town.nativeapp
import org.junit.Assert.*
import org.junit.Test
class TownContractsTest{
    @Test fun waitsForCompleteAssistantReply(){
        val c=PairCodeCollector("pair-1")
        assertNull(c.consume(SSEEvent("tool_result","""{"text":"WRONG1"}""")))
        assertNull(c.consume(SSEEvent("content_block_delta","""{"scene_id":"other","delta":{"text":"WRONG2"}}""")))
        assertNull(c.consume(SSEEvent("content_block_delta","""{"delta":{"text":"AB3"}}""")))
        assertNull(c.consume(SSEEvent("content_block_delta","""{"delta":{"text":"XY9"}}""")))
        assertEquals("AB3XY9",c.consume(SSEEvent("message_stop","{}")))
    }
    @Test fun neverJoinsSeparateReplies(){
        val c=PairCodeCollector("pair")
        c.consume(SSEEvent("content_block_delta","""{"delta":{"text":"ABC"}}"""));assertNull(c.consume(SSEEvent("message_stop","{}")))
        c.consume(SSEEvent("content_block_delta","""{"delta":{"text":"123"}}"""));assertNull(c.consume(SSEEvent("message_stop","{}")))
        c.consume(SSEEvent("content_block_delta","""{"delta":{"text":"ABC123 DEF456"}}"""));assertTrue(runCatching{c.consume(SSEEvent("message_stop","{}"))}.isFailure)
    }
    @Test fun caseSensitiveBoundIdentity(){
        assertEquals("willow",TownContracts.identity(" Willow "));assertEquals("t_Willow",TownContracts.identity("t_Willow"))
        val token="abcdefghijklmnop"
        TownContracts.validatePair("t_Will","t_Willow","willow",token)
        assertTrue(runCatching{TownContracts.validatePair("t_will","t_Willow",null,token)}.isFailure)
        assertTrue(runCatching{TownContracts.validatePair("willow","t_Willow","other",token)}.isFailure)
        assertTrue(runCatching{TownContracts.validatePair("willow","../path","willow",token)}.isFailure)
    }
    @Test fun desktopEventVariants(){
        val c=PairCodeCollector("pair")
        assertNull(c.consume(SSEEvent("message","""{"type":"text","text":"AB3XY9"}""")))
        assertEquals("AB3XY9",c.consume(SSEEvent("message","""{"type":"message_stop"}""")))
        val d=PairCodeCollector("pair")
        d.consume(SSEEvent("text","""{"text":"AB3XY9"}"""))
        assertEquals("AB3XY9",d.consume(SSEEvent("message","[DONE]")))
    }
    @Test fun sceneContracts(){
        assertTrue(SceneRules.validID("desktop-abc:room/1"));assertFalse(SceneRules.validID("other room"))
        assertTrue(SceneRules.validName("方案讨论"));assertFalse(SceneRules.validName("two\nlines"))
        assertEquals("你好",SceneRules.stripTransition("【新消息来自 scene「方案讨论 · ID: desktop-1」】\n\n你好"))
    }
    @Test fun eofFinishesReply(){val c=PairCodeCollector("pair");c.consume(SSEEvent("message","""{"content":"AB3XY9"}"""));assertEquals("AB3XY9",c.finish())}
}
