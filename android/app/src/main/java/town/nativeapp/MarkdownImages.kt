package town.nativeapp

/** Image destinations stay byte-for-byte intact, including signed query strings. */
object MarkdownImages {
    private val image = Regex("""`+[^`]*`+|!\[([^\]]*)\](?:\(<?((?:[^\s<>()]|\([^\s<>()]*\))+)>?(?:\s+"[^"]*")?\)|\[([^\]]*)\])""")
    private val definition = Regex("""^ {0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+"[^"]*")?\s*$""")
    fun definitions(text: String): String {
        var fence: String? = null
        return text.lines().filter { line ->
            val trimmed = line.trim()
            val marker = Regex("^(`{3,}|~{3,})").find(trimmed)?.value
            if (fence != null) {
                if (trimmed.length >= fence!!.length && trimmed.all { it == fence!![0] }) fence = null
                false
            } else if (marker != null) { fence = marker; false }
            else definition.matches(line)
        }.joinToString("\n")
    }
    fun expand(blocks: List<MarkdownBlock>, definitions: String = ""): List<MarkdownBlock> {
        val refs = mutableMapOf<String, String>()
        (listOf(MarkdownBlock("paragraph", definitions)) + blocks).filter { it.kind == "paragraph" }.forEach { b -> b.text.lines().forEach { line ->
            definition.matchEntire(line)?.let { refs.putIfAbsent(it.groupValues[1].lowercase(), it.groupValues[2]) }
        } }
        return blocks.flatMap { block ->
            if (block.kind !in listOf("paragraph", "heading", "quote", "list")) listOf(block)
            else {
                val text = block.text.lines().filterNot { definition.matches(it) }.joinToString("\n")
                val result = mutableListOf<MarkdownBlock>(); var start = 0
                image.findAll(text).filter { it.value.startsWith("!") && (it.range.first == 0 || text[it.range.first - 1] != '\\') }.forEach { m ->
                    val url = m.groups[2]?.value ?: refs[(m.groupValues[3].ifEmpty { m.groupValues[1] }).lowercase()]
                    if (url != null) {
                        if (m.range.first > start) result.add(block.copy(text = text.substring(start, m.range.first)))
                        result.add(MarkdownBlock("image", url, label = m.groupValues[1])); start = m.range.last + 1
                    }
                }
                if (start < text.length) result.add(block.copy(text = text.substring(start)))
                result
            }
        }
    }
}
