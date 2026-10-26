package town.nativeapp

import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay

class LiveHistoryMergeTest {
    @Test fun acceptedActiveSendResumesWithoutDiscardingRecovery() {
        assertTrue(DeliveryRules.shouldRecoverConfirmedSend(true,true,false))
        assertTrue(DeliveryRules.shouldRecoverConfirmedSend(true,false,true))
        assertFalse(DeliveryRules.shouldRecoverConfirmedSend(true,false,false))
        assertFalse(DeliveryRules.shouldRecoverConfirmedSend(false,true,true))
    }
    @Test fun aheadHistoryKeepsOneLiveIdentityEvenWhenAlreadyCached() {
        val prompt=Message("user","question","s",11)
        val live=Message("being","first","s",localBaseline=10,replyTo=prompt.id,localAfter=prompt.id,streaming=true)
        val remote=Message("being","first second final","s",12)
        for(local in listOf(listOf(prompt,live),listOf(prompt,remote,live))) {
            val replies=HistoryRules.merge(local,listOf(prompt,remote)).filter{it.role=="being"}
            assertEquals(1,replies.size);assertEquals(live.id,replies[0].id);assertEquals("first",replies[0].text)
            assertEquals(remote.text,replies[0].persistedText);assertEquals(12,replies[0].sequence)
        }
        val later=Message("user","another question","s",12)
        val unrelated=remote.copy(sequence=13)
        assertEquals(2,HistoryRules.merge(listOf(prompt,live),listOf(prompt,later,unrelated)).count{it.role=="being"})
    }
    @Test fun contentEditsReuseHistoryOrderingAndPreserveSequence() {
        val cache=StreamDisplayCache();val history=emptyList<Message>();var builds=0
        val first=Message("being","first","s",streaming=true)
        fun render(row:Message)=cache.render("s",listOf(row),history,emptySet()){builds++;listOf(row.copy(sequence=12))}
        assertEquals(12,render(first).single().sequence)
        repeat(200){assertEquals("fragment $it",render(first.copy(text="fragment $it")).single().text)}
        assertEquals(1,builds)
        render(first.copy(streaming=false));assertEquals(2,builds)
    }
    @Test fun completedCachedDuplicateDoesNotConsumeAnIdenticalLaterTurn() {
        val prompt=Message("user","question","s",11)
        val local=Message("being","answer","s",localBaseline=10,replyTo=prompt.id,localAfter=prompt.id,streaming=false)
        val remote=Message("being","answer","s",12)
        assertEquals(1,HistoryRules.merge(listOf(prompt,remote,local),listOf(remote)).count{it.role=="being"})
        val next=Message("user","next question","s",12)
        assertEquals(2,HistoryRules.merge(listOf(prompt,local),listOf(next,remote.copy(sequence=13))).count{it.role=="being"})
    }
    @Test fun burstPublishesFirstImmediatelyAndFlushesAllReceivedTextWithoutLateWrites()=runBlocking {
        val snapshots=mutableListOf<String>()
        val frames=StreamPresentation(this){snapshots.add(it.reply)}
        val entry=PendingSend(endpoint="https://example.invalid",sceneID="s",title="s",text="prompt")
        entry.reply="first";frames.submit(entry);assertEquals(listOf("first"),snapshots)
        repeat(2000){entry.reply+="x";frames.submit(entry)}
        assertEquals(1,snapshots.size)
        frames.flush();assertEquals(entry.reply,snapshots.last());assertEquals(2,snapshots.size)
        delay(40);assertEquals(2,snapshots.size)
    }
}
