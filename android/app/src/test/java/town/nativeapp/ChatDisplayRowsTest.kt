package town.nativeapp

import org.junit.Assert.*
import org.junit.Test

class ChatDisplayRowsTest {
    @Test fun segmentsPreserveFencesTablesAndEveryCharacter() {
        val text="Intro\n\n"+"```kotlin\n"+"val x = 1\n\n".repeat(20)+"```\n\n"+
            "| A | B |\n| --- | --- |\n"+"| hello | world |\n".repeat(30)+"\nTail"
        val parts=MarkdownSegments.split(text,80)
        assertEquals(text,parts.joinToString(""))
        assertTrue(parts.any { it.contains("```kotlin")&&it.contains("\n```\n") })
        assertTrue(parts.any { it.contains("| A | B |")&&it.contains("| hello | world |\n".repeat(30)) })
    }
    @Test fun completedRowsKeepIdentityWhileTailGrowsAndFinishPreservesKeys() {
        val projector=ChatDisplayRows()
        val source=Message("being","start",id="reply",streaming=true)
        val body=("Paragraph with enough content to make a long reply.\n\n").repeat(80)
        val first=projector.render(listOf(source)){it.copy(text=body)}
        val next=projector.render(listOf(source)){it.copy(text=body+"Tail grows.")}
        assertTrue(first.size>1)
        assertSame(first.first(),next.first())
        assertEquals(body+"Tail grows.",next.joinToString(""){it.message.text})
        val finished=source.copy(text=body+"Tail grows.",streaming=false)
        val final=projector.render(listOf(finished)){it}
        assertEquals(next.map{it.message.id},final.map{it.message.id})
        assertTrue(final.all{it.source.text==finished.text})
    }
    @Test fun shortLiveTextDoesNotInvalidateTheList() {
        val projector=ChatDisplayRows()
        val source=Message("being","first",streaming=true)
        val first=projector.render(listOf(source)){it}
        val next=projector.render(listOf(source)){it.copy(text="first second")}
        assertSame(first.single(),next.single())
    }
}
