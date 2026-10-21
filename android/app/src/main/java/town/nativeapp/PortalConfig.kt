package town.nativeapp

import org.json.JSONObject
import java.io.File

data class PortalOptions(
    val name: String = "android-portal",
    val files: Boolean = true,
    val web: Boolean = true,
    val exec: Boolean = false,
) {
    fun validated(): PortalOptions {
        require(Regex("[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}").matches(name)) { "名称需为 1–64 位字母、数字、横线或下划线。" }
        return this
    }

    fun toml(workspace: File): String {
        validated()
        return """
            name = ${tomlString(name)}
            workspace = ${tomlString(workspace.absolutePath)}
            bind = "127.0.0.1:0"
            kits_enabled = false
            [tools]
            exec = $exec
            file = $files
            search = $files
            web_fetch = $web
            screenshot = false
            custom_tools_enabled = false
            [security]
            max_file_size = 10485760
            expose_host_details = false
            [subagent]
            enabled = false
            auto_install = false
        """.trimIndent() + "\n"
    }

    companion object {
        // Android JSONObject.quote escapes '/' as '\/', which TOML rejects.
        internal fun tomlString(value: String): String = buildString {
            append('"')
            value.forEach { character ->
                when (character) {
                    '"' -> append("\\\"")
                    '\\' -> append("\\\\")
                    else -> if (character.code < 0x20 || character.code == 0x7f) append("\\u${character.code.toString(16).padStart(4, '0')}") else append(character)
                }
            }
            append('"')
        }
    }
}

object PortalStateRules {
    fun connection(sample: String, nonce: String): String? = runCatching {
        val json = JSONObject(sample)
        if (json.optString("nonce") != nonce || json.optLong("pid") <= 0) return null
        json.optString("state").takeIf { it in setOf("connecting", "connected", "retrying", "invalid") }
    }.getOrNull()
}

/** All app-side file operations apply the same canonical boundary as Portal. */
class PortalWorkspace(val root: File) {
    fun resolve(relative: String): File {
        require(!File(relative).isAbsolute) { "仅可访问 Portal 工作区。" }
        val base = root.canonicalFile
        val file = File(base, relative).canonicalFile
        require(file == base || file.toPath().startsWith(base.toPath())) { "路径超出 Portal 工作区。" }
        return file
    }

    fun list(relative: String): List<File> = resolve(relative).listFiles().orEmpty()
        .filter { runCatching { resolve(it.relativeTo(root.canonicalFile).path) }.isSuccess }
        .sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase() })
        .take(500)

    fun importFile(name: String, input: java.io.InputStream) {
        require(name.isNotBlank() && name != "." && name != ".." && '/' !in name && '\\' !in name) { "文件名无效。" }
        root.mkdirs()
        val destination = resolve(name)
        require(!destination.exists()) { "同名文件已存在，请先重命名文件。" }
        val stage = File.createTempFile(".import-", ".tmp", root)
        try {
            stage.outputStream().use { output ->
                val buffer = ByteArray(8192)
                var total = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= MAX_BYTES) { "文件不能超过 10 MB。" }
                    output.write(buffer, 0, count)
                }
            }
            // Move without replacing: a simultaneous remote write must not be overwritten.
            java.nio.file.Files.move(stage.toPath(), destination.toPath())
        } finally { stage.delete() }
    }

    companion object { const val MAX_BYTES = 10L * 1024 * 1024 }
}
