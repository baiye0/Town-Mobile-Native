package town.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReplyStreamTest {
    private fun pending()=PendingSend(endpoint="https://example.invalid",sceneID="s",title="s",text="你好",baseline=10)
    private fun consume(entry:PendingSend,type:String,json:String="{}")=ReplyStream.consume(type,JSONObject(json),entry)

    @Test fun keepaliveAndProviderSpecificDeltaDoNotDropText() {
        val parser=SSEParser();val entry=pending();val snapshots=mutableListOf<String>()
        val wire=": heartbeat\n\nevent: ping\ndata: keepalive\n\nevent: content_block_delta\ndata: {\"delta\":{\"type\":\"provider_text\",\"text\":\"第一段\"}}\n\nevent: content_block_delta\ndata: {\"delta\":{\"text\":\"第二段\"}}\n\n"
        wire.lineSequence().forEach { line -> parser.line(line)?.let { event -> ReplyStream.payload(event)?.let { value ->
            ReplyStream.consume(event.name,value,entry);snapshots.add(entry.reply)
        } } }
        assertEquals(listOf("第一段","第一段第二段"),snapshots)
        assertFalse(entry.bubbles!!.first().closed)
    }

    @Test fun toolSpeechUsesParagraphsAndStopStartsANewBubble() {
        val entry=pending()
        consume(entry,"content_block_delta","""{"delta":{"text":"先检查。"}}""")
        val first=entry.bubbles!!.first().id
        consume(entry,"thinking","""{"text":""}""");assertTrue(ReplyStream.hasFinalReply(entry))
        consume(entry,"tool_use");assertFalse(ReplyStream.hasFinalReply(entry))
        consume(entry,"text","""{"text":"检查完成。"}""")
        assertEquals("先检查。\n\n检查完成。",entry.reply);assertEquals(1,entry.bubbles!!.size)
        consume(entry,"message_stop");consume(entry,"meta","""{"continuation":true}""")
        consume(entry,"text","""{"text":"下一条回复。"}""")
        assertEquals(listOf("先检查。\n\n检查完成。","下一条回复。"),ReplyStream.messages(entry).map{it.text})
        assertEquals(first,entry.bubbles!!.first().id);assertNotEquals(first,entry.bubbles!!.last().id)
    }

    @Test fun processBelongsToPromptAndSurvivesHistoryWhileStillRunning() {
        val entry=pending();entry.process="核对上下文"
        consume(entry,"content_block_delta","""{"delta":{"thinking":"核对"}}""")
        assertEquals("",entry.reply)
        assertEquals("核对",ReplyStream.reasoningText(JSONObject("""{"delta":{"thinking":"核对"}}""")))
        var rows=ReplyStream.project(emptyList(),entry)
        val remote=Message("user","你好","s",11)
        rows=HistoryRules.merge(rows,listOf(remote))
        entry.process+="，继续检索"
        rows=ReplyStream.project(rows,entry)
        assertEquals(1,rows.count{it.role=="user"})
        assertEquals(entry.userID,rows.first().id);assertEquals(11,rows.first().sequence)
        assertEquals(entry.process,rows.first().process)
        consume(entry,"text","""{"text":"回答"}""")
        rows=ReplyStream.project(rows,entry)
        assertEquals(listOf("你好","回答"),rows.map{it.text})
        assertNull(rows.last().process)
    }

    @Test fun persistenceMetadataAndRestartKeepBubbleIDs() {
        val entry=pending();entry.streamID="stream"
        consume(entry,"text","""{"text":"过程"}""")
        val metadata="""{"persisted":{"kind":"self","from":"partial","seq":12,"stream_id":"stream"}}"""
        consume(entry,"meta",metadata);consume(entry,"meta",metadata)
        consume(entry,"text","""{"text":"终稿"}""")
        consume(entry,"meta","""{"persisted":{"kind":"self","from":"final","seq":13,"stream_id":"stream"}}""")
        consume(entry,"message_stop")
        val restored=PendingSend.read(JSONObject(entry.json().toString()))
        assertEquals(entry.bubbles,restored.bubbles);assertEquals(listOf(12,13),restored.bubbles!!.map{it.sequence})
        assertTrue(ReplyStream.hasFinalReply(restored))
        val local=ReplyStream.messages(restored)
        val remote=listOf(Message("being","过程落库","s",12),Message("being","终稿落库","s",13))
        val merged=HistoryRules.merge(local,remote)
        assertEquals(local.map{it.id},merged.map{it.id});assertEquals(remote.map{it.text},merged.map{it.text})
    }

    @Test fun unfinishedToolProgressIsNotAFinalAnswer() {
        val entry=pending();consume(entry,"text","""{"text":"正在检查"}""")
        consume(entry,"tool_use");consume(entry,"message_stop");ReplyStream.finish(entry)
        assertFalse(ReplyStream.hasFinalReply(entry))
        consume(entry,"content_block_delta","""{"delta":{"text":""}}""")
        assertEquals(1,entry.bubbles!!.size);assertFalse(ReplyStream.hasFinalReply(entry))
    }

    @Test fun historyDoesNotReplaceLiveTextUntilExplicitlyFinished() {
        val live=Message("being","实时文字","s",12,streaming=true)
        val remote=Message("being","服务端正文","s",12)
        val merged=HistoryRules.merge(listOf(live),listOf(remote))
        assertEquals(live.id,merged[0].id);assertEquals("实时文字",merged[0].text);assertEquals("服务端正文",merged[0].persistedText)
        assertEquals("服务端正文",HistoryRules.merge(merged,listOf(remote.copy(streaming=false)))[0].text)
    }

    @Test fun acknowledgedPromptAndLiveReplyStayBeforeNextQueuedQuestion() {
        val first=pending();consume(first,"text","""{"text":"回答一"}""")
        var rows=ReplyStream.project(emptyList(),first)
        val second=pending().copy(text="问题二",afterID=first.replyID)
        rows=ReplyStream.project(rows,second)
        rows=HistoryRules.merge(rows,listOf(Message("user","你好","s",11)))
        assertEquals(listOf("你好","回答一","问题二"),rows.filter{it.text.isNotEmpty()}.map{it.text})
        consume(first,"text","""{"text":"继续"}""")
        rows=ReplyStream.project(rows,first)
        assertEquals(listOf("你好","回答一继续","问题二"),rows.filter{it.text.isNotEmpty()}.map{it.text})
    }

    @Test fun questionQueuedDuringThinkingDoesNotJumpBeforeAcknowledgedPrompt() {
        val first=pending()
        var rows=ReplyStream.project(emptyList(),first)
        assertEquals(1,rows.size)
        val second=pending().copy(text="稍后处理",afterID=rows.last().id)
        rows=HistoryRules.merge(ReplyStream.project(rows,second),listOf(Message("user","你好","s",11)))
        assertEquals(listOf("你好","稍后处理"),rows.map{it.text})
        consume(first,"text","""{"text":"第一条回答"}""")
        rows=ReplyStream.project(rows,first)
        assertEquals(listOf("你好","第一条回答","稍后处理"),rows.map{it.text})
    }

    @Test fun identicalRepliesBindToDifferentIDsAndOlderPromptsCannotMatch() {
        val entry=pending();consume(entry,"text","""{"text":"相同"}""");consume(entry,"message_stop");consume(entry,"text","""{"text":"相同"}""")
        val bound=ReplyStream.bindHistory(listOf(Message("being","相同","s",12),Message("being","相同","s",13)),entry)
        assertEquals(ReplyStream.messages(entry).map{it.id},bound.map{it.id});assertEquals(2,bound.map{it.id}.toSet().size)
        val rows=HistoryRules.merge(ReplyStream.project(emptyList(),pending()),listOf(Message("user","你好","s",9)))
        assertEquals(2,rows.count{it.role=="user"})
    }

    @Test fun queuedQuestionsStayAfterEveryBubbleOfThePrecedingTurn() {
        val first=pending()
        var rows=ReplyStream.project(emptyList(),first)
        val second=pending().copy(text="问题二",afterID=first.userID)
        val third=pending().copy(text="问题三",afterID=second.userID)
        rows=ReplyStream.project(ReplyStream.project(rows,second),third)
        consume(first,"text","""{"text":"第一段回答"}""")
        consume(first,"message_stop")
        consume(first,"text","""{"text":"第二段回答"}""")
        rows=ReplyStream.project(rows,first)
        assertEquals(listOf("你好","第一段回答","第二段回答","问题二","问题三"),rows.map{it.text})
        rows=HistoryRules.merge(rows,listOf(Message("user","你好","s",11),Message("being","第一段回答","s",12)))
        assertEquals(listOf("你好","第一段回答","第二段回答","问题二","问题三"),rows.map{it.text})
        val restored=rows.map{HistoryRules.decodeLocal(HistoryRules.encodeLocal(it))}
        assertEquals(rows.map{it.id},HistoryRules.ordered(restored).map{it.id})
    }

    @Test fun earlyHistoryEchoCanContinueWithoutDuplicateAndCanonicalTextWinsAtEnd() {
        val entry=pending();consume(entry,"text","""{"text":"第一段"}""")
        var rows=HistoryRules.merge(ReplyStream.project(emptyList(),entry),listOf(Message("user","你好","s",11),Message("being","第一段","s",12)))
        consume(entry,"text","""{"text":"第二段"}""");rows=ReplyStream.project(rows,entry)
        assertEquals(2,rows.size);assertEquals("第一段第二段",rows.last().text)
        entry.streamID="stream";consume(entry,"meta","""{"persisted":{"kind":"self","from":"final","seq":12,"stream_id":"stream"}}""")
        rows=HistoryRules.merge(ReplyStream.project(rows,entry),listOf(Message("being","规范正文","s",12)))
        consume(entry,"message_stop");rows=ReplyStream.project(rows,entry)
        assertEquals("规范正文",rows.last().text);assertEquals(entry.replyID,rows.last().id)
    }

    @Test fun indicatorsAndQueueSelectionKeepUnconfirmedSendsIndependent() {
        for(phase in listOf("queued","preparing","sending","waiting")) {
            assertFalse(DeliveryRules.showsRetry(phase));assertFalse(DeliveryRules.skipsQueueHead(phase,false))
        }
        for(phase in listOf("failed","unknown")) {
            assertTrue(DeliveryRules.showsRetry(phase));assertTrue(DeliveryRules.skipsQueueHead(phase,false))
        }
        assertFalse(DeliveryRules.skipsQueueHead("unknown",true));assertTrue(DeliveryRules.skipsQueueHead("stopped",true));assertFalse(DeliveryRules.showsRetry("stopped"))
    }

    @Test fun progressIsScopedAndMetadataDoesNotExtendRecoveryForever() {
        assertFalse(ReplyStream.isProgress("text",JSONObject("""{"text":"SBS","scene_id":null}"""),"s"))
        assertFalse(ReplyStream.isProgress("tool_result",JSONObject("""{"scene_id":"other"}"""),"s"))
        assertFalse(ReplyStream.isProgress("meta",JSONObject("""{"stream_id":"x"}"""),"s"))
        assertTrue(ReplyStream.isProgress("thinking",JSONObject("""{"delta":{"text":"继续"}}"""),"s"))
    }

    @Test fun longRepliesAnchorButReadingHistoryAndFocusedComposerTakePriority() {
        assertEquals(ChatScrollAction.FollowTail,ChatScrollRules.action(true,false,false,true,300,600))
        assertEquals(ChatScrollAction.AnchorReply,ChatScrollRules.action(true,false,false,true,601,600))
        assertEquals(ChatScrollAction.FollowTail,ChatScrollRules.action(true,false,true,true,900,400))
        assertEquals(ChatScrollAction.Hold,ChatScrollRules.action(false,false,false,true,900,400))
        assertEquals(ChatScrollAction.Hold,ChatScrollRules.action(true,true,true,true,900,400))
        assertEquals(ChatScrollAction.FollowTail,ChatScrollRules.action(true,false,false,false,900,400))
    }

    @Test fun legacyCombinedReplyMigratesOnlyWhenFinalSuffixIsUniqueAndInactive() {
        val answer="完整回答".repeat(70)
        val old=Message("being","检查过程\n\n$answer","s")
        val remote=Message("being",answer,"s",12)
        val migrated=HistoryRules.merge(listOf(old),listOf(remote))
        assertEquals(1,migrated.size);assertEquals(answer,migrated[0].text);assertEquals("检查过程",migrated[0].process)
        assertEquals(2,HistoryRules.merge(listOf(old),listOf(remote),setOf(old.id)).size)
        assertEquals(3,HistoryRules.merge(listOf(old),listOf(remote,remote.copy(id="other",sequence=13))).size)
    }

}
