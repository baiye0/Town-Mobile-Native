package town.nativeapp

import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.SnapshotStateObserver
import org.junit.Assert.*
import org.junit.Test

class LiveConversationStoreTest {
    @Test fun tokensInvalidateOnlyTheirRowAndStillPersistLatestText() {
        val store = LiveConversationStore()
        val message = Message("being", "first", id="reply", streaming=true)
        store.rooms = listOf(Room(id="room",endpoint="fixture",messages=listOf(message)))
        Snapshot.sendApplyNotifications()
        val observer = SnapshotStateObserver { it() }
        observer.start()
        var listChanges = 0; var rowChanges = 0
        observer.observeReads("list", { _: String -> listChanges++ }) { store.rooms }
        observer.observeReads("row", { _: String -> rowChanges++ }) { store.displayed(message) }
        Snapshot.notifyObjectsInitialized()
        try {
            assertTrue(store.updateText(0,listOf(message.copy(text="first second"))))
            Snapshot.sendApplyNotifications()
            assertEquals(0,listChanges)
            assertEquals(1,rowChanges)
            assertEquals("first second",store.rooms.single().messages.single().text)
            assertEquals("first second",store.displayed(message).text)
            val final = message.copy(text="confirmed",streaming=false,sequence=42)
            assertFalse(store.updateText(0,listOf(final)))
            store.rooms = listOf(store.rooms.single().copy(messages=listOf(final)))
            Snapshot.sendApplyNotifications()
            assertEquals(1,listChanges)
            assertEquals(final,store.displayed(final))
        } finally { observer.stop(); observer.clear() }
    }

    @Test fun firstVisibleTextAndMetadataMustRebuildTheList() {
        val store=LiveConversationStore()
        val empty=Message("being"," ",id="reply",streaming=true)
        store.rooms=listOf(Room(endpoint="fixture",messages=listOf(empty)))
        assertFalse(store.updateText(0,listOf(empty.copy(text="visible"))))
        assertFalse(store.updateText(0,listOf(empty.copy(sequence=12))))
        assertFalse(store.updateText(0,listOf(empty,empty.copy(id="next"))))
    }
}
