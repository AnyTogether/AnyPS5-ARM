package org.anyps5.anyps5_remote

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/// Remote Play on Android: the launcher's H.264 frames decoded by MediaCodec straight into a
/// Flutter texture, each shown as soon as it is decoded, and its 16-bit stereo sound played
/// through a low-latency AudioTrack. All of it runs on one thread of its own.
class StreamPlayer(private val textures: TextureRegistry, private val channel: MethodChannel) {
    private val thread = HandlerThread("anyps5-stream").apply { start() }
    private val handler = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var codec: MediaCodec? = null
    private var audio: AudioTrack? = null
    private var size = Pair(0, 0)

    /// The texture the frames are drawn into.
    fun open(): Long {
        close()
        val made = textures.createSurfaceProducer()
        made.setSize(1280, 720)
        producer = made
        return made.id()
    }

    fun frame(data: ByteArray, key: Boolean, milliseconds: Long) {
        handler.post {
            try {
                decode(data, key, milliseconds)
            } catch (_: Exception) {
                // A decoder that failed starts again at the next key frame.
                codec?.release()
                codec = null
            }
        }
    }

    private fun decode(data: ByteArray, key: Boolean, milliseconds: Long) {
        val surface = producer?.surface ?: return
        if (codec == null) {
            if (!key) return
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1280, 720)
            if (Build.VERSION.SDK_INT >= 30) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            format.setInteger(MediaFormat.KEY_PRIORITY, 0)
            val made = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            made.configure(format, surface, null, 0)
            made.start()
            codec = made
        }
        val decoder = codec ?: return
        val input = decoder.dequeueInputBuffer(20_000)
        if (input >= 0) {
            val buffer = decoder.getInputBuffer(input) ?: return
            buffer.clear()
            buffer.put(data)
            decoder.queueInputBuffer(input, 0, data.size, milliseconds * 1000, 0)
        }
        val info = MediaCodec.BufferInfo()
        while (true) {
            val output = decoder.dequeueOutputBuffer(info, 0)
            when {
                output >= 0 -> decoder.releaseOutputBuffer(output, true)
                output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> resized(decoder.outputFormat)
                else -> break
            }
        }
    }

    /// The picture's real size: the texture takes it, and Flutter hears of it for its shape.
    private fun resized(format: MediaFormat) {
        val width = if (format.containsKey("crop-right")) format.getInteger("crop-right") - format.getInteger("crop-left") + 1 else format.getInteger(MediaFormat.KEY_WIDTH)
        val height = if (format.containsKey("crop-bottom")) format.getInteger("crop-bottom") - format.getInteger("crop-top") + 1 else format.getInteger(MediaFormat.KEY_HEIGHT)
        if (Pair(width, height) == size) return
        size = Pair(width, height)
        producer?.let { made ->
            made.setSize(width, height)
            if (Build.VERSION.SDK_INT >= 23) codec?.setOutputSurface(made.surface)
        }
        main.post { channel.invokeMethod("size", listOf(width, height)) }
    }

    fun sound(data: ByteArray) {
        handler.post {
            val track = audio ?: makeTrack().also { audio = it }
            track.write(data, 0, data.size, AudioTrack.WRITE_NON_BLOCKING)
        }
    }

    private fun makeTrack(): AudioTrack {
        val format = AudioFormat.Builder().setSampleRate(48000).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build()
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
        // A little more than the least the phone allows: enough not to run dry, little delay.
        val least = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val builder = AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(least * 2, 48000 * 4 / 20)).setTransferMode(AudioTrack.MODE_STREAM)
        if (Build.VERSION.SDK_INT >= 26) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        return builder.build().also { it.play() }
    }

    fun close() {
        handler.post {
            codec?.let {
                try { it.stop() } catch (_: Exception) {}
                it.release()
            }
            codec = null
            audio?.let {
                it.pause()
                it.flush()
                it.release()
            }
            audio = null
            size = Pair(0, 0)
        }
        producer?.release()
        producer = null
    }
}
