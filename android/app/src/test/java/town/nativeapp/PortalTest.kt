package town.nativeapp

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class PortalTest {
    @Test fun staleOrMalformedRuntimeStateCannotShowConnected() {
        assertNull(PortalStateRules.connection("{\"nonce\":\"old\",\"pid\":3,\"state\":\"connected\"}", "new"))
        assertNull(PortalStateRules.connection("{\"nonce\":\"new\",\"pid\":0,\"state\":\"connected\"}", "new"))
        assertNull(PortalStateRules.connection("{\"nonce\":", "new"))
        assertNull(PortalStateRules.connection("{\"nonce\":\"new\",\"pid\":3,\"state\":\"server supplied text\"}", "new"))
        assertEquals("retrying", PortalStateRules.connection("{\"nonce\":\"new\",\"pid\":3,\"state\":\"retrying\"}", "new"))
    }

    @Test fun configEscapesPathsAndRejectsInjectedName() {
        assertEquals("\"/data/user/0/workspace\"", PortalOptions.tomlString("/data/user/0/workspace"))
        assertEquals("\"a\\u000ab\"", PortalOptions.tomlString("a\nb"))
        val text = PortalOptions().toml(File("workspace \"quoted\""))
        assertTrue(text.contains("\\\"quoted\\\""))
        assertTrue(text.contains("exec = false"))
        assertTrue(text.contains("screenshot = false"))
        assertTrue(text.contains("kits_enabled = false"))
        assertFalse(text.contains("connect ="))
        assertThrows(IllegalArgumentException::class.java) { PortalOptions("bad\n[tools]").validated() }
        assertThrows(IllegalArgumentException::class.java) { PortalOptions("").validated() }
    }

    @Test fun workspaceRejectsTraversalAndPreservesExistingFiles() {
        val directory = Files.createTempDirectory("portal-test").toFile()
        try {
            val workspace = PortalWorkspace(File(directory, "workspace"))
            workspace.importFile("中文.txt", "hello".byteInputStream())
            assertEquals("hello", workspace.resolve("中文.txt").readText())
            assertThrows(IllegalArgumentException::class.java) { workspace.resolve("../secret") }
            assertThrows(IllegalArgumentException::class.java) { workspace.importFile("../secret", "x".byteInputStream()) }
            assertThrows(IllegalArgumentException::class.java) { workspace.importFile("中文.txt", "overwrite".byteInputStream()) }
            assertEquals("hello", workspace.resolve("中文.txt").readText())
            assertThrows(IllegalArgumentException::class.java) {
                workspace.importFile("large", ByteArray(PortalWorkspace.MAX_BYTES.toInt() + 1).inputStream())
            }
            assertEquals(listOf("中文.txt"), workspace.list("").map { it.name })
        } finally { directory.deleteRecursively() }
    }
}
