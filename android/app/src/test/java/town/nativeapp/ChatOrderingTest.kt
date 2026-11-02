package town.nativeapp

import org.junit.Assert.*
import org.junit.Test

class ChatOrderingTest {
    @Test fun persistedReplyCannotPrecedeUnacknowledgedPromptAfterLegacyHistory() {
        val legacy=Message("being","legacy reply",sceneID="s",id="old")
        val prompt=Message("user","new prompt",sceneID="s",id="prompt",localAfter="old",localBaseline=10)
        val reply=Message("being","new reply",sceneID="s",id="reply",sequence=12,replyTo="prompt",localAfter="prompt",localBaseline=10)
        assertEquals(listOf("old","prompt","reply"),HistoryRules.ordered(listOf(legacy,prompt,reply)).map{it.id})
    }
    @Test fun laterAcknowledgedBubbleMustFollowEarlierUnacknowledgedBubble() {
        val prompt=Message("user","prompt",sceneID="s",id="prompt",localBaseline=10)
        val first=Message("being","first",sceneID="s",id="first",replyTo="prompt",localAfter="prompt",localBaseline=10)
        val last=Message("being","last",sceneID="s",id="last",sequence=12,replyTo="prompt",localAfter="first",localBaseline=10)
        assertEquals(listOf("prompt","first","last"),HistoryRules.ordered(listOf(last,first,prompt)).map{it.id})
    }
    @Test fun acknowledgedDescendantsDoNotReorderOtherScenesOrServerHistory() {
        val prompt=Message("user","prompt",sceneID="a",id="prompt",localBaseline=10)
        val foreign=Message("being","other scene",sceneID="b",id="foreign",sequence=9,localAfter="prompt")
        val reply=Message("being","reply",sceneID="a",id="reply",sequence=12,localAfter="prompt",replyTo="prompt")
        val older=Message("being","older",sceneID="a",id="older",sequence=10)
        assertEquals(listOf("foreign","older","prompt","reply"),HistoryRules.ordered(listOf(reply,prompt,older,foreign)).map{it.id})
    }
    @Test fun queuedPromptStaysAfterAllBubblesWhenEarlierTurnIsAcknowledged() {
        val old=Message("being","legacy",sceneID="s",id="legacy")
        val prompt=Message("user","first",sceneID="s",id="prompt",localAfter="legacy",localBaseline=10)
        val first=Message("being","interim",sceneID="s",id="first",localAfter="prompt",replyTo="prompt",localBaseline=10)
        val queued=Message("user","next",sceneID="s",id="queued",localAfter="prompt",localBaseline=10)
        val last=Message("being","final",sceneID="s",id="last",sequence=12,localAfter="first",replyTo="prompt",localBaseline=10)
        val rows=listOf(old,prompt,first,queued,last)
        assertEquals(listOf("legacy","prompt","first","last","queued"),HistoryRules.ordered(rows).map{it.id})
        val restored=rows.map{HistoryRules.decodeLocal(HistoryRules.encodeLocal(it))}
        assertEquals(HistoryRules.ordered(rows),HistoryRules.ordered(restored))
    }
}
