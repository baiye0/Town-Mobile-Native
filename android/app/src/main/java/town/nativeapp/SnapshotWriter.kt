package town.nativeapp

import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** One FIFO per file. Opportunistic writes may be coalesced, durable barriers never are. */
internal class SnapshotWriter {
    private val io = Executors.newSingleThreadExecutor { task -> Thread(task, "town-storage").apply { isDaemon = true } }
    private val revision = AtomicLong()

    fun schedule(write: () -> Unit, onFailure: (Exception) -> Unit) {
        val ticket = revision.incrementAndGet()
        io.execute {
            if (revision.get() == ticket) try { write() } catch (e: Exception) { onFailure(e) }
        }
    }

    suspend fun confirm(write: () -> Unit) {
        revision.incrementAndGet()
        val done = CompletableDeferred<Unit>()
        io.execute {
            try { write(); done.complete(Unit) } catch (e: Exception) { done.completeExceptionally(e) }
        }
        done.await()
    }

    // Required for existing synchronous queue mutations: don't report a send/remove
    // as committed until the rename succeeds. Stream checkpoints use schedule().
    fun commit(write: () -> Unit) {
        revision.incrementAndGet()
        io.submit(write).get()
    }
}
