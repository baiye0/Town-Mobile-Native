package town.nativeapp

import androidx.compose.foundation.lazy.LazyListState
import org.junit.Assert.assertEquals
import org.junit.Test

class ChatFollowIntentTest {
    @Test fun reflowCannotResumeFollowingAfterReadingGestureSettles() {
        val controller=ChatScrollController(LazyListState(),reversed=true)
        controller.dragged()
        controller.settled(atBottom=true,towardBottom=true)
        assertEquals(ChatFollowMode.Reading,controller.mode)
        controller.dragEnded()
        controller.settled(atBottom=false,towardBottom=true)
        // IME closure or final Markdown layout makes the footer visible later.
        repeat(3){controller.settled(atBottom=true,towardBottom=true)}
        assertEquals(ChatFollowMode.Reading,controller.mode)
    }

    @Test fun onlyCompletedReturnGestureOrExplicitActionResumesFollowing() {
        val controller=ChatScrollController(LazyListState(),reversed=true)
        controller.dragged();controller.dragEnded(cancelled=true)
        controller.settled(atBottom=true,towardBottom=true)
        assertEquals(ChatFollowMode.Reading,controller.mode)
        controller.dragged();controller.dragEnded()
        controller.settled(atBottom=true,towardBottom=false)
        assertEquals(ChatFollowMode.Reading,controller.mode)
        controller.dragged();controller.dragEnded()
        controller.settled(atBottom=true,towardBottom=true)
        assertEquals(ChatFollowMode.Explicit,controller.mode)
        controller.dragged();controller.bottom();controller.dragEnded()
        controller.settled(atBottom=false,towardBottom=false)
        assertEquals(ChatFollowMode.Explicit,controller.mode)
        controller.dragged();controller.submitted()
        assertEquals(ChatFollowMode.Automatic,controller.mode)
    }
}
