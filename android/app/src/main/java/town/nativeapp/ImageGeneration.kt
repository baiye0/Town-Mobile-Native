package town.nativeapp

import org.json.JSONObject
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

data class GenerationJob(val index: Int, val title: String, val submission: String, val id: String?, val request: String, val error: String?)
data class GenerationReceipt(val being: String, val jobs: List<GenerationJob>)
data class GenerationPart(val text: String, val receipt: Boolean = false)
data class GenerationSnapshot(val id: String, val status: String, val deadline: Long, val delay: Long, val action: Boolean, val images: List<ChatImage>, val availability: String) {
    fun wait(now: Long): Long? = if (status in listOf("queued", "running") && !action && deadline > now) minOf(delay.coerceIn(1000, 60000), deadline - now) else null
    fun notice(now: Long): String = when {
        action || status == "uncertain" || (status in listOf("queued", "running") && deadline <= now) -> "结果待核对，可重新查询"
        availability == "expired" -> "图片已失效，可重新查询"
        else -> mapOf("queued" to "排队中", "running" to "正在生成", "succeeded" to "生成成功", "failed" to "生成失败", "cancelled" to "已取消")[status] ?: "结果待核对"
    }
}
object ImageGeneration {
    private val key = Regex("[A-Za-z0-9_-]{1,128}")
    private val id = Regex("gen_[A-Za-z0-9_-]{1,124}")
    // Android JSONObject.getString coerces numbers/booleans, unlike the JVM test implementation.
    private fun string(o: JSONObject, key: String): String { val value = o.get(key); require(value is String); return value }
    private fun exact(o: JSONObject, vararg keys: String) = o.keys().asSequence().toSet() == keys.toSet()
    private fun nullable(o: JSONObject, key: String): String? { val v = o.get(key); require(v == JSONObject.NULL || v is String && v.length <= 256); return v as? String }
    private fun integer(o: JSONObject, key: String): Long {
        val value = o.get(key); require(value is Number)
        val number = value.toDouble(); require(number.isFinite() && number >= 0 && number <= 9007199254740991.0 && number == kotlin.math.floor(number))
        return number.toLong()
    }
    fun parse(text: String): GenerationReceipt? = runCatching {
        require(text.length <= 65536 && StructuredText.detect(text) == "json")
        val o = JSONObject(text)
        require(exact(o, "type", "version", "being_id", "jobs") && string(o, "type") == "being.image-generation" && o.get("version") == 1 && key.matches(string(o, "being_id")))
        val rows = o.getJSONArray("jobs"); require(rows.length() in 1..24)
        val jobs = (0 until rows.length()).map { i ->
            val j = rows.getJSONObject(i)
            require(exact(j, "index", "title", "submission", "generation_id", "client_request_id", "error_code") && j.get("index") == i + 1)
            val title = string(j, "title"); val submission = string(j, "submission"); val gid = nullable(j, "generation_id"); val request = string(j, "client_request_id")
            require(title.isNotBlank() && title.length <= 200 && submission in listOf("accepted", "rejected", "unknown") && key.matches(request))
            require(gid == null || id.matches(gid)); require(submission != "accepted" || gid != null); require(submission != "rejected" || gid == null)
            GenerationJob(i + 1, title, submission, gid, request, nullable(j, "error_code"))
        }
        require(jobs.map { it.request }.distinct().size == jobs.size)
        val ids = jobs.mapNotNull { it.id }; require(ids.distinct().size == ids.size)
        GenerationReceipt(string(o, "being_id"), jobs)
    }.getOrNull()

    /** Only top-level standalone JSON or permitted fences trigger read-only queries. */
    fun parts(text: String): List<GenerationPart> {
        val result = mutableListOf<GenerationPart>(); var cursor = 0; var plain = 0
        fun emit(start: Int, end: Int, source: String) {
            val candidate = runCatching { (org.json.JSONTokener(source).nextValue() as? JSONObject)?.optString("type") == "being.image-generation" }
                .getOrElse { source.trimStart().startsWith('{') && source.contains(Regex(""""type"\s*:\s*"being\.image-generation"""")) }
            if (candidate) { if (start > plain) result.add(GenerationPart(text.substring(plain, start))); result.add(GenerationPart(source, true)); plain = end }
        }
        while (cursor < text.length) {
            val next = text.indexOf('\n', cursor).let { if (it < 0) text.length else it + 1 }
            val line = text.substring(cursor, next).trimEnd('\n', '\r')
            val fence = Regex("^ {0,3}(`{3,}|~{3,})\\s*(.*)$").matchEntire(line)
            if (fence != null) {
                val mark = fence.groupValues[1]; var close = next; var end = text.length
                while (close < text.length) {
                    val after = text.indexOf('\n', close).let { if (it < 0) text.length else it + 1 }
                    val candidate = text.substring(close, after).trim()
                    if (candidate.length >= mark.length && candidate.all { it == mark[0] }) { end = after; break }; close = after
                }
                if (fence.groupValues[2].trim().lowercase() in listOf("", "json", "being-image-generation")) emit(cursor, end, text.substring(next, close))
                cursor = end; continue
            }
            val objectStart = Regex("""^ {0,3}(\{|\[(?=$|\s|\{|\[|"|\d|\]|-|true\b|false\b|null\b))""").find(line)
            if (objectStart != null) {
                val start = cursor + objectStart.value.length - 1
                var end = start; var depth = 0; var quoted = false; var escaped = false
                while (end < text.length) {
                    val c = text[end++]
                    if (quoted) { if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') quoted = false }
                    else if (c == '"') quoted = true else if (c == '{' || c == '[') depth++ else if ((c == '}' || c == ']') && --depth == 0) break
                }
                if (text[start] == '{') emit(cursor, end, text.substring(start, end))
                cursor = end; continue
            }
            cursor = next
        }
        if (plain < text.length) result.add(GenerationPart(text.substring(plain)))
        return result
    }
    fun snapshot(o: JSONObject, job: GenerationJob): GenerationSnapshot {
        val gid = string(o, "id"); require(id.matches(gid) && (job.id == null || job.id == gid) && string(o, "client_request_id") == job.request)
        val status = string(o, "status"); require(status in listOf("queued", "running", "uncertain", "succeeded", "failed", "cancelled"))
        require(string(o, "stage").length <= 128)
        val deadline = integer(o, "deadline"); val delay = integer(o, "poll_after_ms"); require(deadline > 0)
        val action = nullable(o, "required_action"); require(action == null || action == "operator_reconciliation_required"); nullable(o, "error_code")
        val availability = string(o, "availability"); require(availability in listOf("pending", "available", "expired"))
        val images = mutableListOf<ChatImage>()
        if (status == "succeeded" && availability == "available") {
            val manifest = o.getJSONObject("manifest"); require(manifest.get("version") == 1 && string(manifest, "kind") == "image")
            val outputs = manifest.getJSONArray("outputs"); require(outputs.length() in 1..16)
            for (i in 0 until outputs.length()) {
                val out = outputs.getJSONObject(i); require(string(out, "id").length <= 256)
                val attachment = out.getJSONObject("attachment"); val aid = string(attachment, "attachment_id")
                require(string(attachment, "source") == "being-service" && Regex("att_[A-Za-z0-9_-]{1,124}").matches(aid))
                require(Regex("image/(png|jpeg|webp|gif|avif)").matches(string(out, "mime")))
                val raw = string(out, "view_url"); val url = raw.toHttpUrlOrNull() ?: error("无效图片地址")
                require(ImageTransport.validURL(raw) && url.host == "beings.town" && url.port == 443 && url.fragment == null && url.encodedPath == "/api/being-service/v1/assets/$aid/view" && !url.queryParameter("token").isNullOrEmpty())
                images.add(ChatImage(raw, job.title))
            }
        }
        return GenerationSnapshot(gid, status, deadline, delay, action != null, images, availability)
    }
}
