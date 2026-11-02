package town.nativeapp

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class SnapshotWriterTest {
    @Test fun oldRecoveryCursorCannotResurrectADeletedEntry() = runBlocking {
        val writer = SnapshotWriter()
        val running = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val writes = Collections.synchronizedList(mutableListOf<String>())
        writer.schedule({
            running.countDown()
            check(finish.await(5, TimeUnit.SECONDS))
            writes.add("in flight")
        }) { throw AssertionError(it) }
        assertTrue(running.await(5, TimeUnit.SECONDS))
        writer.schedule({ writes.add("obsolete cursor") }) { throw AssertionError(it) }
        writer.schedule({ writes.add("new cursor") }) { throw AssertionError(it) }
        finish.countDown()
        writer.confirm { writes.add("removed") }
        assertEquals("removed", writes.last())
        assertFalse(writes.contains("obsolete cursor"))
    }
    @Test fun failedBarrierCannotAcknowledgeDelivery() = runBlocking {
        val writer = SnapshotWriter()
        val result = runCatching { writer.confirm { error("disk full") } }
        assertEquals("disk full", result.exceptionOrNull()?.message)
    }
}
