package town.nativeapp

import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.*
import java.io.File

@Composable fun AttachmentAudioView(file: PendingAttachment, source: PendingAttachment, model: TownModel, color: Color) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val scope = rememberCoroutineScope()
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    var localFile by remember { mutableStateOf<File?>(null) }
    var playing by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var position by remember { mutableFloatStateOf(0f) }
    var duration by remember { mutableFloatStateOf(0f) }
    var volume by remember { mutableFloatStateOf(1f) }
    var speed by remember { mutableFloatStateOf(1f) }
    var peaks by remember { mutableStateOf(List(28) { .12f }) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    var menu by remember { mutableStateOf(false) }
    var settings by remember { mutableStateOf(false) }
    var transcript by remember { mutableStateOf("") }
    var transcriptError by remember { mutableStateOf(false) }
    var transcriptRetry by remember { mutableIntStateOf(0) }
    val audioManager = remember { context.getSystemService(AudioManager::class.java) }
    val attributes = remember { AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build() }
    val focus = remember {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener { change -> if (change != AudioManager.AUDIOFOCUS_GAIN) { player?.pause(); playing = false } }.build()
    }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument(file.mime)) { uri ->
        val audio = localFile
        if (uri != null && audio != null) scope.launch {
            try { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { output -> audio.inputStream().use { it.copyTo(output) } } ?: error("无法保存") } }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { error = "音频保存失败，请重试" }
        }
    }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) { player?.pause(); playing = false; audioManager.abandonAudioFocusRequest(focus) } }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); player?.release(); player = null; audioManager.abandonAudioFocusRequest(focus) }
    }
    LaunchedEffect(retry) {
        player?.release(); player = null; playing = false; loading = true; error = null
        var pending: MediaPlayer? = null
        try {
            val connection = model.connection ?: return@LaunchedEffect
            val audio = localFile ?: model.downloadAttachment(connection, source)
            ensureActive()
            if (model.connection != connection) return@LaunchedEffect
            localFile = audio
            val ready = MediaPlayer(); pending = ready
            withContext(Dispatchers.IO) { ready.setAudioAttributes(attributes); ready.setDataSource(audio.path); ready.prepare() }
            ensureActive()
            ready.setOnCompletionListener { playing = false; position = duration; audioManager.abandonAudioFocusRequest(focus) }
            ready.setOnErrorListener { failed, _, _ ->
                playing = false; error = "音频暂时无法播放"
                if (player === failed) player = null
                failed.release(); audioManager.abandonAudioFocusRequest(focus); true
            }
            ready.setVolume(volume, volume)
            duration = ready.duration / 1000f; position = 0f; player = ready; pending = null; loading = false
            peaks = withContext(Dispatchers.Default) { audioWaveform(audio) }
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { error = "音频暂时无法播放" }
        finally { pending?.release(); loading = false }
    }
    LaunchedEffect(file.resultID, transcriptRetry) {
        val connection = model.connection ?: return@LaunchedEffect
        val id = file.attachmentID ?: return@LaunchedEffect
        val version = file.resultID ?: return@LaunchedEffect
        transcriptError = false
        try {
            val text = model.parsedText(connection, id, version)
            if (model.connection == connection) transcript = AudioTranscript.display(text)
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { transcriptError = true }
    }
    LaunchedEffect(playing) {
        while (playing) { position = (player?.currentPosition ?: 0) / 1000f; delay(200) }
    }
    val seek: (Float) -> Unit = { value -> position = value.coerceIn(0f, duration); player?.seekTo((position * 1000).toInt()) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(file.name, color = color, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
        Surface(color = Color(0xff292929), contentColor = Color.White, shape = RoundedCornerShape(14.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = {
                    val audio = player
                    if (audio == null || error != null) { retry++ }
                    else try {
                        if (playing) { audio.pause(); playing = false; audioManager.abandonAudioFocusRequest(focus) }
                        else if (audioManager.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                            if (position >= duration) seek(0f)
                            audio.playbackParams = audio.playbackParams.setSpeed(speed)
                            audio.start(); playing = true
                        } else error = "音频暂时无法播放"
                    } catch (_: Exception) { error = "音频暂时无法播放"; playing = false }
                }, enabled = !loading, modifier = Modifier.size(44.dp)) {
                    if (loading) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    else Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "暂停" else "播放")
                }
                Canvas(Modifier.weight(1f).height(44.dp)
                    .pointerInput(duration) { detectTapGestures { seek(it.x / size.width.coerceAtLeast(1) * duration) } }
                    .pointerInput(duration) { detectDragGestures { change, _ -> change.consume(); seek(change.position.x / size.width.coerceAtLeast(1) * duration) } }
                    .semantics {
                        contentDescription = "播放进度"
                        progressBarRangeInfo = ProgressBarRangeInfo(position, 0f..duration.coerceAtLeast(1f))
                        setProgress { seek(it); true }
                    }) {
                    val step = size.width / peaks.size
                    peaks.forEachIndexed { index, peak ->
                        val x = step * (index + .5f); val half = 14.dp.toPx() * peak
                        drawLine(if (index.toFloat() / peaks.size <= position / duration.coerceAtLeast(1f)) Color.White else Color.Gray, Offset(x, size.height / 2 - half), Offset(x, size.height / 2 + half), (step * .55f).coerceAtLeast(1f), StrokeCap.Round)
                    }
                }
                Text("${audioTime(position)} / ${if (duration > 0) audioTime(duration) else "—"}", Modifier.padding(start = 6.dp), fontSize = 10.sp, maxLines = 1)
                Box {
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(36.dp)) { Icon(Icons.Default.MoreHoriz, "音频操作") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("播放设置") }, onClick = { menu = false; settings = true })
                        DropdownMenuItem(text = { Text("保存音频") }, enabled = localFile != null, onClick = { menu = false; save.launch(file.name) })
                    }
                }
            }
        }
        error?.let { TextButton(onClick = { retry++ }) { Text("$it · 重试", color = color) } }
        if (transcript.isNotEmpty()) SelectionContainer { Text(transcript, color = color, style = MaterialTheme.typography.bodyMedium) }
        if (transcriptError) TextButton(onClick = { transcriptRetry++ }) { Text("语音文字加载失败，重试", color = color) }
    }
    if (settings) AlertDialog(onDismissRequest = { settings = false }, title = { Text("播放设置") }, text = {
        Column {
            Text("音量")
            Slider(value = volume, onValueChange = { volume = it; player?.setVolume(it, it) }, modifier = Modifier.semantics { contentDescription = "音量" })
            Text("播放速度")
            listOf(.5f, .75f, 1f, 1.25f, 1.5f, 2f).forEach { rate ->
                TextButton(onClick = { speed = rate; if (playing) player?.let { it.playbackParams = it.playbackParams.setSpeed(rate) } }) { Text("${if (speed == rate) "✓ " else ""}${rate}×") }
            }
        }
    }, confirmButton = { TextButton(onClick = { settings = false }) { Text("完成") } })
}

private fun audioTime(seconds: Float): String {
    val value = if (seconds.isFinite()) seconds.toInt().coerceAtLeast(0) else 0
    return "%d:%02d".format(java.util.Locale.ROOT, value / 60, value % 60)
}
