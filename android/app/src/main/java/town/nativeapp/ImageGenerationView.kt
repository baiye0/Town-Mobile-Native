package town.nativeapp

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject

@Composable fun GeneratedMessageText(text: String, message: Message, model: TownModel, color: Color) {
    val parts = remember(text, message.streaming, message.role) { if (message.streaming == true || message.role != "being") listOf(GenerationPart(text)) else ImageGeneration.parts(text) }
    val definitions = remember(text) { MarkdownImages.definitions(text) }
    val seen = mutableSetOf<String>()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        parts.forEachIndexed { index, part ->
            if (!part.receipt) MarkdownText(part.text, textColor = color, imageReferences = definitions)
            else {
                val receipt = remember(part.text) { ImageGeneration.parse(part.text) }
                if (receipt == null) {
                    Text("图片回执格式无效，请修复回执后重试", color = color)
                    MarkdownText(part.text, textColor = color)
                } else if (seen.add(receipt.being + receipt.jobs.joinToString { "${it.id}:${it.request}" })) {
                    key(model.connection, message.id, message.sceneID, index, part.text) { GenerationReceiptView(receipt, model.connection) }
                }
            }
        }
    }
}

@Composable private fun GenerationReceiptView(receipt: GenerationReceipt, connection: Connection?) {
    val endpoint = connection?.endpoint?.toHttpUrlOrNull()
    if (connection == null || receipt.being != connection.being || endpoint?.host != "echo.beings.town" || endpoint.port != 443 || !endpoint.isHttps) {
        Text("回执与当前连接不匹配，或当前 Heart 未配置生图服务"); return
    }
    val snapshots = remember { mutableStateMapOf<Int, GenerationSnapshot>() }
    var preview by remember { mutableStateOf<String?>(null) }
    val images = receipt.jobs.flatMap { snapshots[it.index]?.images ?: emptyList() }
    receipt.jobs.forEach { job -> key(job.request) {
        GenerationJobView(job, connection) { snapshots[job.index] = it }
        snapshots[job.index]?.images?.forEach { image -> RemoteImage(image, onOpen = { preview = image.url }) }
    } }
    preview?.let { selected -> if (images.isNotEmpty()) ImageGallery(images, images.indexOfFirst { it.url == selected }.coerceAtLeast(0)) { preview = null } }
}

@Composable private fun GenerationJobView(job: GenerationJob, connection: Connection, update: (GenerationSnapshot) -> Unit) {
    var notice by remember { mutableStateOf(if (job.submission == "rejected") "提交未受理：${job.error ?: "未知原因"}" else "正在查询") }
    var busy by remember { mutableStateOf(false) }; var retry by remember { mutableIntStateOf(0) }
    val onUpdate by rememberUpdatedState(update)
    LaunchedEffect(retry) {
        if (job.submission == "rejected") return@LaunchedEffect
        var failures = 0; var resolved = job.id
        while (isActive) {
            busy = true
            try {
                val route = resolved ?: "by-request/${job.request}"
                val request = Request.Builder().url("https://beings.town/api/being-service/v1/generations/$route")
                    .header("Authorization", "Bearer ${connection.token}").header("X-Being-Id", connection.being).header("Accept", "application/json").build()
                val bytes = ImageTransport.read(request, 1024 * 1024)
                val json = bytes.toString(Charsets.UTF_8)
                require(StructuredText.detect(json) == "json")
                val result = ImageGeneration.snapshot(JSONObject(json), job.copy(id = resolved))
                ensureActive(); onUpdate(result); resolved = result.id; failures = 0
                val now = System.currentTimeMillis(); notice = result.notice(now); busy = false
                val wait = result.wait(now) ?: break
                delay(wait)
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                busy = false; failures++
                val permanent = e is IllegalArgumentException || e is org.json.JSONException || e is ImageQueryException && e.status in listOf(400, 401, 403, 404, 405, 409)
                val again = !permanent && failures < 5
                notice = if (again) "查询中断，正在重连…" else "暂时无法查询，请核对连接和回执后重新查询"
                if (!again) break
                delay(minOf(2000L shl (failures - 1), 30000L))
            }
        }
    }
    Column {
        Text(job.title, style = MaterialTheme.typography.titleSmall)
        Row { if (busy) CircularProgressIndicator(Modifier.size(16.dp)); Text(notice, style = MaterialTheme.typography.bodySmall) }
        if (!busy && job.submission != "rejected") TextButton(onClick = { retry++ }) { Text("重新查询") }
    }
}
