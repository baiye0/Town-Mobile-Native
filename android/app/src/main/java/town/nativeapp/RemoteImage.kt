package town.nativeapp

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object ImageTransport {
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .callTimeout(30, TimeUnit.SECONDS).build()
    fun validURL(raw: String): Boolean = raw.length <= 16384 && raw.toHttpUrlOrNull()?.let {
        it.isHttps && it.username.isEmpty() && it.password.isEmpty()
    } == true
    suspend fun read(request: Request, limit: Long, image: Boolean = false): ByteArray {
        var current = request
        repeat(6) {
            try { return readOnce(current, limit, image) }
            catch (redirect: ImageRedirect) {
                require(image && validURL(redirect.url))
                current = Request.Builder().url(redirect.url).header("Accept", "image/*").build()
            }
        }
        error("图片重定向过多")
    }
    suspend fun imageBytes(source: String): ByteArray {
        if (source.startsWith("data:")) return withContext(Dispatchers.Default) {
            require(source.length <= 50 * 1024 * 1024 * 4 / 3 + 128)
            val match = Regex("data:image/(?:png|jpeg|gif|webp|avif);base64,([A-Za-z0-9+/=]+)").matchEntire(source) ?: error("无效图片")
            java.util.Base64.getDecoder().decode(match.groupValues[1]).also { require(it.size <= 50 * 1024 * 1024) }
        }
        require(validURL(source))
        return read(Request.Builder().url(source).header("Accept", "image/*").build(), 50L * 1024 * 1024, true)
    }
    private class ImageRedirect(val url: String) : IOException()
    private suspend fun readOnce(request: Request, limit: Long, image: Boolean): ByteArray = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) { if (!continuation.isCancelled) continuation.resumeWithException(e) }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val bytes = response.use {
                        if (image && it.code in listOf(301, 302, 303, 307, 308)) {
                            val next = it.header("Location")?.let { location -> request.url.resolve(location) } ?: error("无效重定向")
                            throw ImageRedirect(next.toString())
                        }
                        if (!it.isSuccessful) throw ImageQueryException(it.code)
                        val body = it.body ?: error("空响应")
                        require(body.contentLength() <= limit)
                        if (image) require(body.contentType()?.let { t -> t.type == "image" && t.subtype in listOf("png", "jpeg", "gif", "webp", "avif") } == true)
                        val output = java.io.ByteArrayOutputStream()
                        body.byteStream().use { input ->
                            val buffer = ByteArray(16384)
                            while (true) { val n = input.read(buffer); if (n < 0) break; require(output.size().toLong() + n <= limit); output.write(buffer, 0, n) }
                        }; output.toByteArray()
                    }
                    if (!continuation.isCancelled) continuation.resume(bytes)
                } catch (e: Exception) { if (!continuation.isCancelled) continuation.resumeWithException(e) }
            }
        })
    }
}
internal class ImageQueryException(val status: Int) : IOException("查询失败（HTTP $status）")
data class ChatImage(val url: String, val label: String)

@Composable fun RemoteImage(image: ChatImage, onOpen: (() -> Unit)? = null, fullScreen: Boolean = false, inlineMaxHeight: androidx.compose.ui.unit.Dp = 260.dp) {
    var bitmap by remember(image.url) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    var failed by remember(image.url) { mutableStateOf(false) }
    var retry by remember(image.url) { mutableIntStateOf(0) }
    var preview by remember(image.url) { mutableStateOf(false) }
    LaunchedEffect(image.url, retry) {
        failed = false
        try {
            val bytes = ImageTransport.imageBytes(image.url)
            bitmap = withContext(Dispatchers.Default) {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0)
                val options = BitmapFactory.Options().apply { inSampleSize = 1 }
                while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > (if (fullScreen) 2048 else 1024)) options.inSampleSize *= 2
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.asImageBitmap() ?: error("无法解码图片")
            }
        } catch (e: CancellationException) { throw e } catch (_: Exception) { failed = true }
    }
    var scale by remember(image.url) { mutableFloatStateOf(1f) }
    var offset by remember(image.url) { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    val transform = rememberTransformableState { zoom, pan, _ -> scale = (scale * zoom).coerceIn(1f, 5f); offset = if (scale == 1f) androidx.compose.ui.geometry.Offset.Zero else offset + pan }
    Box((if (fullScreen) Modifier.fillMaxSize() else Modifier.fillMaxWidth().heightIn(min = 140.dp, max = inlineMaxHeight)), contentAlignment = Alignment.Center) {
        bitmap?.let { value ->
            Image(value, image.label.ifBlank { "查看图片" },
                (if (fullScreen) Modifier.fillMaxSize().graphicsLayer(scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y).transformable(transform)
                 else Modifier.fillMaxWidth().heightIn(max = inlineMaxHeight).clickable { if (onOpen != null) onOpen() else preview = true }), contentScale = ContentScale.Fit)
        } ?: if (failed) TextButton(onClick = { retry++ }) { Text("图片加载失败，点击重试") } else CircularProgressIndicator()
    }
    if (preview) ImageGallery(listOf(image), 0) { preview = false }
}

@Composable fun ImageGallery(images: List<ChatImage>, initial: Int, close: () -> Unit) {
    var selected by remember { mutableStateOf(images[initial].url) }
    val index = images.indexOfFirst { it.url == selected }.coerceAtLeast(0)
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Color.Black).padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("${index + 1} / ${images.size}", Modifier.weight(1f), color = Color.White)
                TextButton(onClick = close) { Text("关闭", color = Color.White) }
            }
            Box(Modifier.weight(1f).clipToBounds()) { key(images[index].url) { RemoteImage(images[index], fullScreen = true) } }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(enabled = index > 0, onClick = { selected = images[index - 1].url }) { Text("上一张") }
                TextButton(enabled = index < images.lastIndex, onClick = { selected = images[index + 1].url }) { Text("下一张") }
            }
        }
    }
}
