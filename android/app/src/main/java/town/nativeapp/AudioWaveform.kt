package town.nativeapp

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.CancellationException
import java.io.File
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max

// Decode in small buffers. Large/long recordings retain the desktop's neutral bars.
suspend fun audioWaveform(file: File): List<Float> {
    val fallback = List(28) { .12f }
    if (file.length() > 16L * 1024 * 1024) return fallback
    val extractor = MediaExtractor()
    var decoder: MediaCodec? = null
    try {
        extractor.setDataSource(file.path)
        val track = (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: return fallback
        val format = extractor.getTrackFormat(track)
        val duration = format.getLong(MediaFormat.KEY_DURATION)
        if (duration <= 0 || duration > 600_000_000) return fallback
        extractor.selectTrack(track)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!); decoder = codec
        codec.configure(format, null, null, 0); codec.start()
        var inputDone = false
        var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var encoding = AudioFormat.ENCODING_PCM_16BIT
        val peaks = FloatArray(28)
        val info = MediaCodec.BufferInfo()
        val deadline = android.os.SystemClock.elapsedRealtime() + 8000
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            currentCoroutineContext().ensureActive()
            if (!inputDone) {
                val index = codec.dequeueInputBuffer(1000)
                if (index >= 0) {
                    val buffer = codec.getInputBuffer(index)!!
                    val count = extractor.readSampleData(buffer, 0)
                    if (count < 0) { codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true }
                    else { codec.queueInputBuffer(index, 0, count, extractor.sampleTime, 0); extractor.advance() }
                }
            }
            val index = codec.dequeueOutputBuffer(info, 1000)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val output = codec.outputFormat
                sampleRate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE); channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                encoding = if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) output.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
            } else if (index >= 0) {
                val buffer = codec.getOutputBuffer(index)!!.order(ByteOrder.nativeOrder())
                buffer.position(info.offset); buffer.limit(info.offset + info.size)
                val bytes = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                var sample = 0
                while (buffer.remaining() >= bytes) {
                    val value = if (bytes == 4) abs(buffer.float) else abs(buffer.short.toFloat()) / 32768f
                    if (sample % channels == 0) {
                        val time = info.presentationTimeUs + sample / channels * 1_000_000L / sampleRate
                        val bin = (time * 28 / duration).toInt().coerceIn(0, 27)
                        peaks[bin] = max(peaks[bin], value)
                    }
                    sample++
                }
                codec.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    val peak = max(peaks.maxOrNull() ?: 0f, .001f)
                    return peaks.map { max(.12f, it / peak) }
                }
            }
        }
    } catch (e: CancellationException) { throw e }
    catch (_: Exception) { /* Waveform decoding must never prevent playback. */ }
    finally { runCatching { decoder?.stop() }; decoder?.release(); extractor.release() }
    return fallback
}
