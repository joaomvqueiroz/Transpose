package com.example.transpose_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/** QA-only local microphone probe. PCM never enters a channel, file, or log. */
class QaBandAcousticProbe private constructor(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "transpose/qa_band_acoustic")
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    @Volatile private var recorder: AudioRecord? = null
    @Volatile private var state: Map<String, Any?> = mapOf("phase" to "idle", "busy" to false)

    init {
        check(context.packageName.endsWith(".qa")) { "Acoustic capture is QA-only" }
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "status" -> reply.success(state + ("busy" to busy.get()))
                "start" -> {
                    val durationMs = call.argument<Int>("durationMs") ?: 10_000
                    val beatIntervalMs = call.argument<Int>("beatIntervalMs") ?: 500
                    when {
                        durationMs !in 10_000..15_000 || beatIntervalMs !in 250..1500 ->
                            reply.error("INVALID_CAPTURE", "Use 10–15 s e intervalo de 250–1500 ms.", null)
                        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ->
                            reply.error("MIC_PERMISSION", "Autorize o microfone antes da prova acústica QA.", null)
                        !QaMicrophoneLease.active.compareAndSet(false, true) ->
                            reply.error("BUSY", "Já há uma captação acústica no processo.", null)
                        !busy.compareAndSet(false, true) -> {
                            QaMicrophoneLease.active.set(false)
                            reply.error("BUSY", "Captação acústica já em curso.", null)
                        }
                        else -> {
                            cancelled.set(false)
                            state = mapOf("phase" to "capturing", "busy" to true)
                            worker.execute { capture(durationMs, beatIntervalMs) }
                            reply.success(null)
                        }
                    }
                }
                "cancel" -> { cancel(); reply.success(null) }
                else -> reply.notImplemented()
            }
        }
    }

    private data class Effects(
        val aec: AcousticEchoCanceler?,
        val agc: AutomaticGainControl?,
        val ns: NoiseSuppressor?,
    ) {
        fun metadata(): Map<String, Any?> = mapOf(
            "aecEnabled" to aec?.enabled,
            "agcEnabled" to agc?.enabled,
            "noiseSuppressorEnabled" to ns?.enabled,
        )
        fun release() {
            try { aec?.release() } catch (_: Exception) {}
            try { agc?.release() } catch (_: Exception) {}
            try { ns?.release() } catch (_: Exception) {}
        }
    }

    private fun disableEffects(session: Int): Effects {
        fun <T : android.media.audiofx.AudioEffect> create(make: () -> T?): T? =
            try { make()?.also { it.setEnabled(false) } } catch (_: Exception) { null }
        return Effects(
            create { if (AcousticEchoCanceler.isAvailable()) AcousticEchoCanceler.create(session) else null },
            create { if (AutomaticGainControl.isAvailable()) AutomaticGainControl.create(session) else null },
            create { if (NoiseSuppressor.isAvailable()) NoiseSuppressor.create(session) else null },
        )
    }

    private fun buildRecorder(): Pair<AudioRecord, Int> {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val supportsRaw = manager.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        val preferred = if (supportsRaw) MediaRecorder.AudioSource.UNPROCESSED else MediaRecorder.AudioSource.VOICE_RECOGNITION
        val sources = if (preferred == MediaRecorder.AudioSource.UNPROCESSED)
            intArrayOf(preferred, MediaRecorder.AudioSource.VOICE_RECOGNITION) else intArrayOf(preferred)
        val format = AudioFormat.Builder().setSampleRate(QaBandAcousticAnalyzer.RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
        val minimum = AudioRecord.getMinBufferSize(QaBandAcousticAnalyzer.RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Microfone PCM 48 kHz indisponível." }
        for (source in sources) {
            val record = try {
                AudioRecord.Builder().setAudioSource(source).setAudioFormat(format)
                    .setBufferSizeInBytes(max(minimum * 2, 9600)).build()
            } catch (_: Exception) { null }
            if (record?.state == AudioRecord.STATE_INITIALIZED) return record to source
            record?.release()
        }
        error("Não foi possível iniciar o microfone QA.")
    }

    private fun capture(durationMs: Int, beatIntervalMs: Int) {
        var record: AudioRecord? = null
        var effects: Effects? = null
        var samples: ShortArray? = null
        val scratch = ShortArray(480)
        try {
            if (cancelled.get()) throw InterruptedException()
            val (created, source) = buildRecorder()
            record = created
            recorder = created
            effects = disableEffects(created.audioSessionId)
            val frames = durationMs * QaBandAcousticAnalyzer.RATE / 1000
            samples = ShortArray(frames)
            created.startRecording()
            check(created.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microfone não começou a gravar." }
            var initialRoute: AudioDeviceInfo? = null
            var changedRoute = false
            val initialStamp = AudioTimestamp()
            val finalStamp = AudioTimestamp()
            var stampAtStart = false
            var stampAtEnd = false
            var offset = 0
            while (offset < frames) {
                if (cancelled.get()) throw InterruptedException()
                val count = created.read(scratch, 0, minOf(scratch.size, frames - offset), AudioRecord.READ_BLOCKING)
                if (count <= 0) {
                    if (cancelled.get()) throw InterruptedException()
                    error("Falha na leitura do microfone: $count")
                }
                if (!stampAtStart) stampAtStart = created.getTimestamp(initialStamp, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS
                System.arraycopy(scratch, 0, samples, offset, count)
                offset += count
                val current = created.routedDevice
                if (initialRoute == null) initialRoute = current
                else if (current?.id != initialRoute?.id) changedRoute = true
            }
            stampAtEnd = created.getTimestamp(finalStamp, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS
            created.stop()
            if (cancelled.get()) throw InterruptedException()
            state = mapOf("phase" to "analyzing", "busy" to true)
            val metrics = QaBandAcousticAnalyzer.analyze(samples, beatIntervalMs)
            if (cancelled.get()) throw InterruptedException()
            val captureClockErrorMs = if (stampAtStart && stampAtEnd && finalStamp.framePosition > initialStamp.framePosition) {
                val actual = (finalStamp.nanoTime - initialStamp.nanoTime) / 1_000_000.0
                val expected = (finalStamp.framePosition - initialStamp.framePosition) * 1000.0 / QaBandAcousticAnalyzer.RATE
                actual - expected
            } else null
            val metadata = mapOf(
                "sampleRate" to QaBandAcousticAnalyzer.RATE,
                "frames" to frames,
                "durationMs" to durationMs,
                "source" to if (source == MediaRecorder.AudioSource.UNPROCESSED) "UNPROCESSED" else "VOICE_RECOGNITION",
                "routeId" to initialRoute?.id,
                "routeType" to initialRoute?.type,
                "routeChanged" to changedRoute,
                "timestampValid" to (stampAtStart && stampAtEnd),
                "captureClockErrorMs" to captureClockErrorMs,
            ) + effects.metadata()
            val clockSafe = captureClockErrorMs == null || kotlin.math.abs(captureClockErrorMs) <= 5.0
            val routeSafe = !changedRoute && initialRoute?.type == AudioDeviceInfo.TYPE_BUILTIN_MIC
            state = mapOf(
                "phase" to if (metrics.conclusive && routeSafe && clockSafe) "done" else "inconclusive",
                "busy" to true,
                "reason" to (when {
                    !routeSafe -> "Rota do microfone alterada ou não integrada."
                    !clockSafe -> "Timestamp de captação descontínuo."
                    else -> metrics.reason
                }),
                "metrics" to metrics.asMap(),
                "capture" to metadata,
            )
        } catch (_: InterruptedException) {
            state = mapOf("phase" to "cancelled", "busy" to true)
        } catch (failure: Exception) {
            state = mapOf("phase" to "error", "busy" to true,
                "error" to (failure.message ?: "Falha na captação acústica QA."))
        } finally {
            try { record?.let { if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop() } } catch (_: Exception) {}
            effects?.release()
            record?.release()
            recorder = null
            samples?.fill(0)
            scratch.fill(0)
            busy.set(false)
            QaMicrophoneLease.active.set(false)
        }
    }

    fun cancel() {
        cancelled.set(true)
        try { recorder?.stop() } catch (_: Exception) {}
    }

    fun close() {
        cancel()
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    companion object {
        fun attach(context: Context, messenger: BinaryMessenger): QaBandAcousticProbe? =
            if (context.packageName.endsWith(".qa")) QaBandAcousticProbe(context.applicationContext, messenger) else null
    }
}
