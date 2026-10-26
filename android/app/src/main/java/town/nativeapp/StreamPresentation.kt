package town.nativeapp

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** First packet is immediate; subsequent snapshots share a display frame. No synthetic typing. */
class StreamPresentation(private val scope:CoroutineScope,private val publish:(PendingSend)->Unit) {
    private var pending:PendingSend?=null
    private var task:Job?=null
    fun submit(entry:PendingSend) {
        val snapshot=entry.copy(files=entry.files.toMutableList())
        if(task==null) {
            publish(snapshot)
            task=scope.launch {
                while(true) {
                    delay(16)
                    val next=pending ?: break
                    pending=null;publish(next)
                }
                task=null
            }
        } else pending=snapshot
    }
    fun flush() {
        task?.cancel();task=null
        val next=pending ?: return
        pending=null;publish(next)
    }
}
