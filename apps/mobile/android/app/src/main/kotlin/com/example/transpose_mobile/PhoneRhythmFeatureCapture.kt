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

/** QA-only ambient rhythm features. No WebView access, PCM file, or PCM channel payload. */
class PhoneRhythmFeatureCapture private constructor(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "transpose/qa_phone_rhythm_features")
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val finishRequested = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    @Volatile private var recorder: AudioRecord? = null
    @Volatile private var state: Map<String, Any?> = mapOf("phase" to "idle", "busy" to false)
    private var completed: RhythmFeatureExtractor? = null
    private var completedOriginUs: Long? = null

    init {
        check(context.packageName == QA_PACKAGE) { "Rhythm microphone capture is QA-only." }
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "clock" -> reply.success(System.nanoTime() / 1000)
                "status" -> reply.success(state + ("busy" to busy.get()))
                "start" -> {
                    val durationMs = call.argument<Int>("durationMs") ?: 60_000
                    when {
                        durationMs !in 1_000..600_000 ->
                            reply.error("INVALID_DURATION", "Capture must last 1 s to 10 min.", null)
                        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ->
                            reply.error("MIC_PERMISSION", "Microphone permission is required for QA capture.", null)
                        !QaMicrophoneLease.active.compareAndSet(false, true) ->
                            reply.error("BUSY", "A QA microphone capture is already active.", null)
                        !busy.compareAndSet(false, true) -> {
                            QaMicrophoneLease.active.set(false)
                            reply.error("BUSY", "Capture is already active.", null)
                        }
                        else -> {
                            completed?.clear()
                            completed = null
                            completedOriginUs = null
                            finishRequested.set(false)
                            cancelled.set(false)
                            state = mapOf("phase" to "capturing", "busy" to true,
                                "maxDurationMs" to durationMs, "featureRateHz" to 100)
                            worker.execute { capture(durationMs) }
                            reply.success(null)
                        }
                    }
                }
                "finish" -> {
                    if (busy.get()) finishRequested.set(true)
                    reply.success(null)
                }
                "cancel" -> { cancel(); reply.success(null) }
                "readFeatures" -> {
                    val offset = call.argument<Int>("offset") ?: 0
                    val limit = call.argument<Int>("limit") ?: 500
                    val source = completed
                    when {
                        busy.get() || source == null -> reply.error("NOT_READY", "Finish capture first.", null)
                        offset < 0 || limit !in 1..1000 -> reply.error("INVALID_PAGE", "Use offset>=0, limit 1..1000.", null)
                        else -> reply.success(mapOf(
                            "offset" to offset,
                            "total" to source.features.size,
                            "windowMs" to 10,
                            "features" to source.page(offset, limit).map { feature ->
                                mapOf(
                                    "frameStart" to feature.frameStart,
                                    "relativeMs" to feature.frameStart / 48.0,
                                    "monotonicUs" to completedOriginUs?.let {
                                        it + feature.frameStart * 1_000_000L / RhythmFeatureExtractor.RATE
                                    },
                                    "rms" to feature.rms,
                                    "novelty" to feature.novelty,
                                    "onset" to feature.onset,
                                )
                            },
                        ))
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private data class Effects(
        val aec: AcousticEchoCanceler?,
        val agc: AutomaticGainControl?,
        val ns: NoiseSuppressor?,
    ) {
        fun status(): Map<String, Any?> = mapOf(
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
        val raw = manager.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        val sources = if (raw) intArrayOf(MediaRecorder.AudioSource.UNPROCESSED,
            MediaRecorder.AudioSource.VOICE_RECOGNITION)
            else intArrayOf(MediaRecorder.AudioSource.VOICE_RECOGNITION)
        val minimum = AudioRecord.getMinBufferSize(RhythmFeatureExtractor.RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "48 kHz mono microphone unavailable." }
        val format = AudioFormat.Builder().setSampleRate(RhythmFeatureExtractor.RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
        for (source in sources) {
            val candidate = try {
                AudioRecord.Builder().setAudioSource(source).setAudioFormat(format)
                    .setBufferSizeInBytes(max(minimum * 2, 9600)).build()
            } catch (_: Exception) { null }
            if (candidate?.state == AudioRecord.STATE_INITIALIZED) return candidate to source
            candidate?.release()
        }
        error("Could not initialize QA microphone.")
    }

    private fun capture(durationMs: Int) {
        var record: AudioRecord? = null
        var effects: Effects? = null
        val extractor = RhythmFeatureExtractor()
        val scratch = ShortArray(RhythmFeatureExtractor.WINDOW_FRAMES)
        val stamps = ArrayList<Pair<Long, Long>>()
        val startCallUs = System.nanoTime() / 1000
        var initialRoute: AudioDeviceInfo? = null
        var routeChanged = false
        var lastReadAtUs: Long? = null
        var maxReadGapUs = 0L
        var source = MediaRecorder.AudioSource.VOICE_RECOGNITION
        try {
            if (cancelled.get()) throw InterruptedException()
            val built = buildRecorder()
            record = built.first
            source = built.second
            recorder = record
            effects = disableEffects(record.audioSessionId)
            record.startRecording()
            check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                "Microphone did not start recording."
            }
            var nextStampFrame = 0L
            val maximumFrames = durationMs.toLong() * RhythmFeatureExtractor.RATE / 1000
            while (extractor.framesSeen < maximumFrames && !finishRequested.get()) {
                if (cancelled.get()) throw InterruptedException()
                val length = minOf(scratch.size.toLong(), maximumFrames - extractor.framesSeen).toInt()
                val count = try {
                    record.read(scratch, 0, length, AudioRecord.READ_BLOCKING)
                } catch (failure: Exception) {
                    if (cancelled.get()) throw InterruptedException()
                    throw failure
                }
                if (count <= 0) {
                    if (cancelled.get()) throw InterruptedException()
                    error("Microphone read failed: $count")
                }
                val readAtUs = System.nanoTime() / 1000
                lastReadAtUs?.let { maxReadGapUs = max(maxReadGapUs, readAtUs - it) }
                lastReadAtUs = readAtUs
                try {
                    extractor.accept(scratch, count)
                } finally {
                    // The only PCM array is erased after every read, including failures.
                    scratch.fill(0)
                }
                val route = record.routedDevice
                if (initialRoute == null && route != null) initialRoute = route
                else if (initialRoute != null && route?.id != initialRoute.id) routeChanged = true
                if (extractor.framesSeen >= nextStampFrame) {
                    val stamp = AudioTimestamp()
                    if (record.getTimestamp(stamp, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS) {
                        stamps.add(stamp.framePosition to stamp.nanoTime)
                    }
                    nextStampFrame = extractor.framesSeen + RhythmFeatureExtractor.RATE
                }
                if (extractor.features.size % 100 == 0) {
                    state = mapOf("phase" to "capturing", "busy" to true,
                        "featureCount" to extractor.features.size, "onsetCount" to extractor.onsetCount,
                        "maxDurationMs" to durationMs, "featureRateHz" to 100)
                }
            }
            if (cancelled.get()) throw InterruptedException()
            extractor.finish()
            try { record.stop() } catch (_: Exception) {}
            val originEstimates = stamps.map { (frame, nanos) ->
                nanos / 1000 - frame * 1_000_000L / RhythmFeatureExtractor.RATE
            }.sorted()
            val originSpreadUs = if (originEstimates.size >= 2)
                originEstimates.last() - originEstimates.first() else null
            val validClock = originEstimates.size >= 2 && originSpreadUs != null && originSpreadUs <= 5000
            val originUs = if (validClock) originEstimates[originEstimates.size / 2] else null
            val meanRms = if (extractor.features.isEmpty()) 0.0 else
                extractor.features.sumOf { it.rms } / extractor.features.size
            val effectEnabled = effects?.let {
                it.aec?.enabled == true || it.agc?.enabled == true || it.ns?.enabled == true
            } == true
            val quality = when {
                routeChanged -> "routeChanged"
                initialRoute?.type != AudioDeviceInfo.TYPE_BUILTIN_MIC -> "nonBuiltinMicrophone"
                !validClock -> "captureClockUncertain"
                maxReadGapUs > 250_000 -> "captureReadStall"
                extractor.clippedSamples > extractor.framesSeen / 100 -> "clipping"
                effectEnabled -> "audioEffectsActive"
                else -> "availableForReview"
            }
            completed = extractor
            completedOriginUs = originUs
            state = mapOf(
                "phase" to "done", "busy" to false,
                "quality" to quality,
                "featureCount" to extractor.features.size,
                "featureRateHz" to 100,
                "framesSeen" to extractor.framesSeen,
                "onsetCount" to extractor.onsetCount,
                "peakRms" to extractor.peakRms,
                "meanRms" to meanRms,
                "ambientRms" to extractor.ambientRms,
                "clippedSamples" to extractor.clippedSamples,
                "sampleRate" to RhythmFeatureExtractor.RATE,
                "source" to if (source == MediaRecorder.AudioSource.UNPROCESSED)
                    "UNPROCESSED" else "VOICE_RECOGNITION",
                "routeId" to initialRoute?.id,
                "routeType" to initialRoute?.type,
                "routeChanged" to routeChanged,
                "startCallMonotonicUs" to startCallUs,
                "endCallMonotonicUs" to System.nanoTime() / 1000,
                "captureOriginMonotonicUs" to originUs,
                "captureClockSpreadUs" to originSpreadUs,
                "captureTimestampCount" to stamps.size,
                "maxReadGapUs" to maxReadGapUs,
            ) + (effects?.status() ?: emptyMap())
        } catch (_: InterruptedException) {
            extractor.clear()
            completed = null
            completedOriginUs = null
            state = mapOf("phase" to "cancelled", "busy" to false)
        } catch (failure: Exception) {
            extractor.clear()
            completed = null
            completedOriginUs = null
            state = mapOf("phase" to "error", "busy" to false,
                "error" to (failure.message ?: "QA rhythm feature capture failed."))
        } finally {
            try { record?.let { if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop() } }
            catch (_: Exception) {}
            effects?.release()
            record?.release()
            recorder = null
            scratch.fill(0)
            busy.set(false)
            QaMicrophoneLease.active.set(false)
        }
    }

    fun cancel() {
        cancelled.set(true)
        finishRequested.set(true)
        try { recorder?.stop() } catch (_: Exception) {}
        if (!busy.get()) {
            completed?.clear()
            completed = null
            completedOriginUs = null
            state = mapOf("phase" to "cancelled", "busy" to false)
        }
    }

    fun close() {
        cancel()
        completed?.clear()
        completed = null
        completedOriginUs = null
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    companion object {
        private const val QA_PACKAGE = "com.example.transpose_mobile.qa"
        fun attach(context: Context, messenger: BinaryMessenger): PhoneRhythmFeatureCapture? =
            if (context.packageName == QA_PACKAGE)
                PhoneRhythmFeatureCapture(context.applicationContext, messenger) else null
    }
}
