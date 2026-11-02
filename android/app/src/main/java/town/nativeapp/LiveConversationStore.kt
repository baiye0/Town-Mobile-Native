package town.nativeapp

import androidx.compose.runtime.*

/** Text frames invalidate their own row; topology and acknowledgements invalidate the list. */
internal class LiveConversationStore {
    private var revision by mutableIntStateOf(0)
    private var stored: List<Room> = emptyList()
    private val text = mutableMapOf<String, MutableState<String?>>()
    var rooms: List<Room>
        get() { revision; return stored }
        set(value) {
            stored = value
            text.values.forEach { it.value = null }
            val retained = value.flatMap { it.messages }.mapTo(hashSetOf()) { it.id }
            text.keys.retainAll(retained)
            revision++
        }

    fun displayed(message: Message): Message {
        val live = text.getOrPut(message.id) { mutableStateOf(null) }.value
        return if (live == null || live == message.text) message else message.copy(text = live)
    }

    fun updateText(room: Int, next: List<Message>): Boolean {
        val before = stored[room].messages
        if (before.size != next.size) return false
        val changed = before.indices.filter { before[it] != next[it] }
        if (changed.any { index ->
            val old = before[index]; val new = next[index]
            old.role != "being" || old.streaming != true || new.streaming != true ||
                old.text.isNotBlank() != new.text.isNotBlank() || old.copy(text = new.text) != new
        }) return false
        if (changed.isEmpty()) return true
        stored = stored.toMutableList().also { it[room] = stored[room].copy(messages = next) }
        changed.forEach { index ->
            val message = next[index]
            text.getOrPut(message.id) { mutableStateOf(null) }.value = message.text
        }
        return true
    }
}
