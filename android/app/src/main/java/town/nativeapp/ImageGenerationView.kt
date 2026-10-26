package town.nativeapp

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject

@Composable fun GeneratedMessageText(text: String, message: Message, model: TownModel, color: Color) {
    val parts = remember(text, message.streaming, message.role) { if (message.role != "being") listOf(GenerationPart(text)) else ImageGeneration.parts(text) }
    val definitions = remember(text) { MarkdownImages.definitions(text) }
    val seen = mutableSetOf<String>()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        parts.forEachIndexed { index, part ->
            if (!part.receipt) MarkdownText(part.text, textColor = color, imageReferences = definitions)
            else if (message.streaming == true) Text("正在接收图片任务回执…", color = color)
            else {
                val receipt = remember(part.text) { ImageGeneration.parse(part.text) }
                if (receipt == null) {
                    Text("图片回执格式无效，请让 Being 仅修正回执，不要重新生成。", color = color)
                    MarkdownText(part.text, textColor = color)
                } else if (seen.add(receipt.being + receipt.jobs.joinToString { "${it.id}:${it.request}" })) {
                    key(model.connection, message.id, message.sceneID, index, part.text) { GenerationReceiptView(receipt, model.connection) }
                }
            }
        }
    }
}

@Composable private fun GenerationReceiptView(receipt: GenerationReceipt, connection: Connection?) {
    val snapshots = remember { mutableStateMapOf<Int, GenerationSnapshot>() }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text("生成图片", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("${receipt.jobs.size} 张", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    val endpoint = connection?.endpoint?.toHttpUrlOrNull()
    if (connection == null || receipt.being != connection.being || endpoint?.host != "echo.beings.town" || endpoint.port != 443 || !endpoint.isHttps) {
        Text("回执与当前连接不匹配，或当前 Heart 未配置生图服务"); return
    }
    var preview by remember { mutableStateOf<String?>(null) }
    val images = receipt.jobs.flatMap { snapshots[it.index]?.images ?: emptyList() }
    receipt.jobs.forEach { job -> key(job.request) {
        GenerationJobView(job, connection, open = { preview = it }) { snapshots[job.index] = it }
    } }
    preview?.let { selected -> if (images.isNotEmpty()) ImageGallery(images, images.indexOfFirst { it.url == selected }.coerceAtLeast(0)) { preview = null } }
}

@Composable private fun GenerationJobView(job: GenerationJob, connection: Connection, open: (String) -> Unit, update: (GenerationSnapshot) -> Unit) {
    var notice by remember { mutableStateOf(if (job.submission == "rejected") "提交未受理：${job.error ?: "未知原因"}" else "正在查询") }
    var snapshot by remember { mutableStateOf<GenerationSnapshot?>(null) }
    val onUpdate by rememberUpdatedState(update)
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            if (job.submission == "rejected") return@repeatOnLifecycle
            var failures = 0; var resolved = job.id
            while (isActive) {
                try {
                    val route = resolved ?: "by-request/${job.request}"
                    val request = Request.Builder().url("https://beings.town/api/being-service/v1/generations/$route")
                        .header("Authorization", "Bearer ${connection.token}").header("X-Being-Id", connection.being).header("Accept", "application/json").header("Cache-Control", "no-store").build()
                    val bytes = ImageTransport.read(request, 1024 * 1024)
                    val json = bytes.toString(Charsets.UTF_8)
                    require(StructuredText.detect(json) == "json")
                    val result = ImageGeneration.snapshot(JSONObject(json), job.copy(id = resolved))
                    ensureActive(); snapshot = result; onUpdate(result); resolved = result.id; failures = 0
                    val now = System.currentTimeMillis(); notice = result.notice(now)
                    val wait = result.wait(now) ?: break
                    delay(wait)
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) {
                    failures++
                    val permanent = e is IllegalArgumentException || e is org.json.JSONException || e is ImageQueryException && e.status in listOf(400, 401, 403, 404, 405, 409)
                    val again = !permanent && failures < 5
                    notice = if (again) "正在重新连接…" else "暂时无法获取图片"
                    if (!again) break
                    delay(minOf(2000L shl (failures - 1), 30000L))
                }
            }
        }
    }
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val images = snapshot?.images.orEmpty()
        if (images.isEmpty()) {
            Box(Modifier.fillMaxWidth().heightIn(min = 96.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f), RoundedCornerShape(14.dp)).padding(12.dp), contentAlignment = Alignment.Center) {
                Text(notice.replace("，可重新查询", ""), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else images.forEach { image ->
            Box(Modifier.clip(RoundedCornerShape(14.dp))) { RemoteImage(image, onOpen = { open(image.url) }, inlineMaxHeight = 360.dp) }
        }
        Text(job.title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
    }
}
