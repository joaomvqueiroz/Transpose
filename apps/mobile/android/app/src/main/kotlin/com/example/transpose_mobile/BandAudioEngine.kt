package com.example.transpose_mobile

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.*

/** A continuously primed PCM track. Silence warms the output; beat positions
 * are placed on the track's presentation clock, never on a UI/Dart timer. */
class BandAudioEngine(messenger: BinaryMessenger, private val qaAcousticEnabled: Boolean = false) {
    private data class Plan(val revision: Int, val startUs: Long, val bpm: Double,
        val beats: Int, val validUntilUs: Long, val correctionUs: Long)
    private val channel = MethodChannel(messenger, "transpose/band_audio")
    private val executor = Executors.newSingleThreadExecutor()
    private val generation = AtomicInteger(0)
    @Volatile private var plan: Plan? = null
    @Volatile private var running = false
    @Volatile private var prepared = false
    @Volatile private var qaRole: String? = null
    @Volatile private var status: Map<String, Any?> = emptyMap()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "clock" -> result.success(System.nanoTime() / 1000)
                "setQaAcousticRole" -> {
                    val requested = call.arguments as? String
                    if (!qaAcousticEnabled || requested !in listOf("A", "B")) {
                        result.error("QA_ONLY", "Acoustic role is available only to the QA app.", null)
                    } else {
                        qaRole = requested
                        result.success(null)
                    }
                }
                "prepare" -> {
                    if (!prepared) {
                        prepared = true
                        val run = generation.incrementAndGet()
                        status = mapOf("locked" to false, "running" to false)
                        executor.execute { render(run) }
                    }
                    result.success(null)
                }
                "schedule" -> {
                    val args = call.arguments as? Map<*, *>
                    val revision = (args?.get("revision") as? Number)?.toInt()
                    val start = (args?.get("startUs") as? Number)?.toLong()
                    val bpm = (args?.get("bpm") as? Number)?.toDouble()
                    val beats = (args?.get("beats") as? Number)?.toInt()
                    val expiry = (args?.get("validUntilUs") as? Number)?.toLong()
                    val correction = (args?.get("correctionUs") as? Number)?.toLong()
                    if (revision == null || start == null || bpm == null || !bpm.isFinite() || bpm < 40.0 || bpm > 240.0 ||
                        beats == null || beats !in 1..12 || expiry == null || correction == null ||
                        abs(correction) > 500000 || expiry > System.nanoTime() / 1000 + 3000000) {
                        result.error("INVALID_PLAN", "Invalid metronome schedule", null)
                    } else {
                        plan = Plan(revision, start, bpm, beats, expiry, correction)
                        result.success(null)
                    }
                }
                "status" -> result.success(status + mapOf(
                    "running" to running, "generation" to generation.get()))
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    fun stop() {
        plan = null
        prepared = false
        generation.incrementAndGet()
        status = mapOf("locked" to false, "leaseActive" to false)
    }

    fun interrupt() {
        stop()
        status = mapOf("locked" to false, "error" to "Saída interrompida; volte a entrar na sessão.")
    }

    fun close() {
        stop()
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun render(run: Int) {
        var track: AudioTrack? = null
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val rate = 48000
            val minimum = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT)
            check(minimum > 0) { "PCM output unavailable" }
            val builder = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(rate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(max(minimum * 2, 3840))
            if (Build.VERSION.SDK_INT >= 26) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            track = builder.build()
            check(track.state == AudioTrack.STATE_INITIALIZED) { "PCM initialization failed" }
            val block = ShortArray(480)
            val stamp = AudioTimestamp()
            var written = 0L
            var origin = 0.0
            var locked = false
            var previousFrame = -1L
            var previousStampUs = 0L
            var queryAt = 0L
            var route = -1
            var revision = -1
            var lastBeat = -1L
            var clickFrame = 1200
            var accent = false
            var count = 0L
            var maxGridErrorUs = 0.0
            var underruns = 0
            var lastStatus = 0L
            track.play()
            running = true
            while (run == generation.get()) {
                val now = System.nanoTime() / 1000
                val newRoute = track.routedDevice?.id ?: -1
                if (newRoute != route || track.underrunCount != underruns) {
                    route = newRoute
                    underruns = track.underrunCount
                    locked = false
                    previousFrame = -1L
                    queryAt = 0L
                    clickFrame = 1200
                }
                if (now >= queryAt) {
                    if (track.getTimestamp(stamp) && stamp.framePosition > previousFrame) {
                        val measured = stamp.nanoTime / 1000.0 - stamp.framePosition * 1000000.0 / rate
                        if (previousFrame >= 0 && stamp.nanoTime / 1000 > previousStampUs) {
                            // Reject route jumps; reacquire before producing another click.
                            if (locked && abs(measured - origin) > 20000) {
                                locked = false
                                clickFrame = 1200
                            } else {
                                origin = measured
                                locked = true
                            }
                        } else origin = measured
                        previousFrame = stamp.framePosition
                        previousStampUs = stamp.nanoTime / 1000
                    } else if (now - previousStampUs > 15000000) locked = false
                    queryAt = now + if (locked) 10000000 else 100000
                }
                val p = plan
                if (p != null && p.revision != revision) {
                    revision = p.revision
                    lastBeat = -1L
                    clickFrame = 1200
                }
                for (i in block.indices) {
                    var sample = 0.0
                    val presentationUs = origin + (written + i) * 1000000.0 / rate
                    if (locked && p != null && now < p.validUntilUs && presentationUs < p.validUntilUs) {
                        val interval = 60000000.0 / p.bpm
                        val elapsed = presentationUs + p.correctionUs - p.startUs
                        val beat = floor(elapsed / interval).toLong()
                        val phaseUs = elapsed - beat * interval
                        // Joining/recovering starts only at a future beat, never mid-click.
                        if (beat >= 0 && beat > lastBeat && phaseUs < 1000000.0 / rate * 1.5) {
                            lastBeat = beat
                            clickFrame = 0
                            accent = beat % p.beats == 0L
                            count++
                            maxGridErrorUs = max(maxGridErrorUs, phaseUs)
                        }
                        if (clickFrame < 1200) {
                            val phase = clickFrame / 1199.0
                            val frequency = when (qaRole) {
                                "A" -> if (accent) 1500 else 1000
                                "B" -> if (accent) 3500 else 2500
                                else -> if (accent) 1800 else 1100
                            }
                            sample = sin(2 * PI * frequency * clickFrame / rate) *
                                sin(PI * phase) * exp(-5 * phase) * (if (accent) .8 else .6)
                            clickFrame++
                        }
                    } else clickFrame = 1200
                    block[i] = (sample * 32767).roundToInt().toShort()
                }
                var offset = 0
                while (offset < block.size && run == generation.get()) {
                    val size = track.write(block, offset, block.size - offset, AudioTrack.WRITE_BLOCKING)
                    check(size > 0) { "PCM write failed: $size" }
                    offset += size
                    written += size
                }
                if (now - lastStatus > 200000) {
                    lastStatus = now
                    status = mapOf("locked" to locked, "clicks" to count,
                        "maxGridErrorUs" to maxGridErrorUs, "underruns" to underruns,
                        "route" to route, "timestampAgeMs" to (now - previousStampUs) / 1000,
                        "leaseActive" to (p != null && now < p.validUntilUs))
                }
            }
        } catch (e: Exception) {
            if (run == generation.get()) {
                status = mapOf("locked" to false, "error" to (e.message ?: "Audio output failed"))
            }
        } finally {
            track?.let { try { it.pause(); it.flush(); it.release() } catch (_: Exception) {} }
            running = false
        }
    }
}
