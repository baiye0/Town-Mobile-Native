package town.nativeapp
import org.junit.Assert.*
import org.junit.Test
class ProtocolTest {
    @Test fun validatesConnection() {
        val c = Connection.parse("https://example.com/willow/?token=abc_123&relay_secret=xyz")
        assertEquals("https://example.com/willow", c.endpoint)
        assertEquals("xyz", c.secret)
        assertEquals("100", c.url("/api/history?limit=100").queryParameter("limit"))
        for (link in listOf("http://example.com/a?token=x", "https://u:p@example.com/a?token=x", "https://example.com/a/b?token=x", "https://example.com/a?token=", "https://example.com/a?token=x&secret=%0d")) {
            assertTrue(runCatching { Connection.parse(link) }.isFailure)
        }
    }
    @Test fun parsesMultilineEvents() {
        val p = SSEParser()
        assertNull(p.line(": keepalive")); assertNull(p.line("event: content_block_delta\r"))
        assertNull(p.line("data: {\"delta\":")); assertNull(p.line("data: {\"text\":\"你好\"}}"))
        assertEquals(SSEEvent("content_block_delta", "{\"delta\":\n{\"text\":\"你好\"}}"), p.line(""))
        assertNull(p.line("")); p.line("data: next"); assertEquals("message", p.line("")!!.name)
    }
    @Test fun flushesUnterminatedFinalFrameAtEof() {
        val p = SSEParser(); p.line("event: text"); p.line("data: {\"text\":\"末帧\"}")
        assertEquals(SSEEvent("text", "{\"text\":\"末帧\"}"), p.line(""))
    }
}
