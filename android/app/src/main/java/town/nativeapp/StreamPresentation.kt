package town.nativeapp

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Called on the main dispatcher. Keep every token, publish at most every 50 ms. */
class StreamPresentation(private val scope:CoroutineScope,private val publish:(PendingSend)->Unit) {
    private var pending:PendingSend?=null
    private var task:Job?=null
    fun submit(entry:PendingSend) {
        pending=entry.copy(files=entry.files.toMutableList())
        if(task==null)task=scope.launch { delay(50);flush() }
    }
    fun flush() {
        task?.cancel();task=null
        val entry=pending ?: return
        pending=null;publish(entry)
    }
}
