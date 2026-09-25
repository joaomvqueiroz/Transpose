package com.example.transpose_mobile

import android.content.Context
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.pow

/** One Media3 output per channel; the probe and app never share a player. */
class Media3ChannelPlayer(
    context: Context,
    messenger: BinaryMessenger,
    channelName: String,
) {
    private val channel = MethodChannel(messenger, channelName)
    private val appContext = context.applicationContext
    private var player: ExoPlayer? = null
    private var mediaUri: Uri? = null
    private var originalDurationMs: Long = -1
    private var loopStartMs: Long = -1
    private var loopEndMs: Long = -1
    private var loopEnabled = false
    private var loopCount = 0L
    // Epoch/count describe complete A->B cycles, not backwards positions or
    // elapsed wall time. Epochs also invalidate observations after a user seek.
    private var loopEpoch = 0L
    private var loopCycleArmed = false
    private var loopMediaItemId: String? = null
    private var snapshotRevision = 0L
    private var interruptionRevision = 0L
    private var interruptionReason = ""

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "prepare", "load" -> {
                        val uri = call.argument<String>("uri")
                            ?: call.argument<String>("path")?.let { Uri.fromFile(File(it)).toString() }
                            ?: throw IllegalArgumentException("Missing media URI")
                        val parsed = Uri.parse(uri)
                        require(parsed.scheme == "file" || parsed.scheme == "content") {
                            "Only local media URIs are supported"
                        }
                        if (parsed.scheme == "file") {
                            require(File(parsed.path ?: "").isFile) { "Input file does not exist" }
                        }
                        releasePlayer()
                        val next = ExoPlayer.Builder(appContext)
                            .setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(C.USAGE_MEDIA)
                                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                                    .build(),
                                true,
                            )
                            .setHandleAudioBecomingNoisy(true)
                            .build()
                        next.addListener(object : Player.Listener {
                            override fun onPlaybackSuppressionReasonChanged(reason: Int) {
                                if (reason == Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS) {
                                    interrupt(next, "audioFocus")
                                }
                            }

                            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                                if (!playWhenReady &&
                                    (reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS ||
                                        reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY)
                                ) {
                                    interrupt(next, if (reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY) {
                                        "audioRoute"
                                    } else {
                                        "audioFocus"
                                    })
                                }
                            }

                            override fun onMediaItemTransition(
                                mediaItem: MediaItem?,
                                reason: Int,
                            ) {
                                if (player !== next || !loopEnabled ||
                                    reason != Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT ||
                                    mediaItem?.mediaId != loopMediaItemId
                                ) return
                                // Starting/seeking halfway through A/B does not
                                // constitute a repetition. The next transition
                                // puts playback at A and arms a complete cycle.
                                if (loopCycleArmed) loopCount++
                                loopCycleArmed = true
                            }
                        })
                        player = next
                        mediaUri = parsed
                        next.setMediaItem(MediaItem.fromUri(parsed))
                        next.prepare()
                        result.success(snapshot(next))
                    }
                    "play" -> {
                        val current = requirePlayer()
                        val expectedRevision = call.argument<Number>("interruptionRevision")?.toLong()
                        if (expectedRevision != null && expectedRevision != interruptionRevision) {
                            // A pre-interruption request that arrived late must not restart output.
                            result.success(snapshot(current))
                            return@setMethodCallHandler
                        }
                        current.play()
                        result.success(snapshot(current))
                    }
                    "pause" -> {
                        val current = requirePlayer()
                        current.pause()
                        result.success(snapshot(current))
                    }
                    "seek" -> {
                        val current = requirePlayer()
                        val positionMs = (call.argument<Number>("positionMs")
                            ?: throw IllegalArgumentException("Missing position")).toLong()
                        require(positionMs >= 0)
                        if (loopEnabled && (positionMs < loopStartMs || positionMs >= loopEndMs)) {
                            clearLoop(current)
                        }
                        beginLoopEpoch(loopEnabled && positionMs == loopStartMs)
                        if (loopEnabled) {
                            // Keep the current item's identity: a seek changes
                            // counting scope, not the prepared clipping source.
                            loopMediaItemId = current.currentMediaItem?.mediaId
                        }
                        current.seekTo(if (loopEnabled) positionMs - loopStartMs else positionMs)
                        result.success(snapshot(current))
                    }
                    "setLoop" -> {
                        val current = requirePlayer()
                        val startMs = (call.argument<Number>("startMs")
                            ?: throw IllegalArgumentException("Missing A")).toLong()
                        val endMs = (call.argument<Number>("endMs")
                            ?: throw IllegalArgumentException("Missing B")).toLong()
                        require(startMs >= 0 && endMs > startMs)
                        require(originalDurationMs > 0 && endMs <= originalDurationMs)
                        val uri = mediaUri ?: throw IllegalStateException("No media URI")
                        val positionMs = absolutePosition(current)
                        val keepPlaying = current.playWhenReady
                        val revision = interruptionRevision
                        loopStartMs = startMs
                        loopEndMs = endMs
                        loopEnabled = true
                        val relative = if (positionMs >= startMs && positionMs < endMs) {
                            positionMs - startMs
                        } else {
                            0L
                        }
                        beginLoopEpoch(relative == 0L)
                        loopMediaItemId = "transpono-loop-$loopEpoch"
                        val clipping = MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(startMs)
                            .setEndPositionMs(endMs)
                            .build()
                        current.setMediaItem(MediaItem.Builder().setUri(uri)
                            .setMediaId(loopMediaItemId!!)
                            .setClippingConfiguration(clipping).build())
                        current.repeatMode = Player.REPEAT_MODE_ONE
                        current.prepare()
                        current.seekTo(relative)
                        current.playWhenReady = keepPlaying && revision == interruptionRevision
                        result.success(snapshot(current))
                    }
                    "clearLoop" -> {
                        val current = requirePlayer()
                        if (loopEnabled) clearLoop(current)
                        result.success(snapshot(current))
                    }
                    "setParameters" -> {
                        val current = requirePlayer()
                        val semitones = (call.argument<Number>("semitones")
                            ?: throw IllegalArgumentException("Missing semitones")).toDouble()
                        val speed = (call.argument<Number>("speed")
                            ?: throw IllegalArgumentException("Missing speed")).toDouble()
                        require(semitones.isFinite() && semitones in -12.0..12.0)
                        require(speed.isFinite() && speed in 0.5..2.0)
                        val pitch = 2.0.pow(semitones / 12.0).toFloat()
                        current.playbackParameters = PlaybackParameters(speed.toFloat(), pitch)
                        result.success(snapshot(current))
                    }
                    "snapshot" -> result.success(snapshot(requirePlayer()))
                    "release" -> {
                        releasePlayer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("NATIVE_PROCESSING_PROBE", error.message, null)
            }
        }
    }

    private fun requirePlayer(): ExoPlayer =
        player ?: throw IllegalStateException("Probe has no prepared player")

    private fun interrupt(current: ExoPlayer, reason: String) {
        if (player !== current) return
        interruptionRevision++
        interruptionReason = reason
        // ExoPlayer owns focus. Cancel its pending play intent so a later focus
        // gain or headset reconnection cannot resume without another user play.
        current.pause()
    }

    private fun absolutePosition(current: ExoPlayer): Long =
        if (loopEnabled) loopStartMs + current.currentPosition else current.currentPosition

    private fun beginLoopEpoch(armed: Boolean = false) {
        loopEpoch++
        loopCount = 0
        loopCycleArmed = armed
    }

    private fun clearLoop(current: ExoPlayer) {
        val uri = mediaUri ?: throw IllegalStateException("No media URI")
        val positionMs = absolutePosition(current)
        val keepPlaying = current.playWhenReady
        val revision = interruptionRevision
        loopEnabled = false
        beginLoopEpoch()
        loopMediaItemId = null
        current.repeatMode = Player.REPEAT_MODE_OFF
        current.setMediaItem(MediaItem.fromUri(uri))
        current.prepare()
        current.seekTo(positionMs)
        current.playWhenReady = keepPlaying && revision == interruptionRevision
    }

    private fun snapshot(current: ExoPlayer): Map<String, Any> {
        snapshotRevision++
        if (!loopEnabled && current.duration > 0) {
            originalDurationMs = current.duration
        }
        return mapOf(
        "playbackState" to current.playbackState,
        "snapshotRevision" to snapshotRevision,
        "ready" to (current.playbackState == Player.STATE_READY),
        "ended" to (current.playbackState == Player.STATE_ENDED),
        "playing" to current.isPlaying,
        "playWhenReady" to current.playWhenReady,
        "interruptionRevision" to interruptionRevision,
        "interruptionReason" to interruptionReason,
        "positionMs" to absolutePosition(current),
        "durationMs" to (if (originalDurationMs > 0) originalDurationMs else current.duration),
        "speed" to current.playbackParameters.speed.toDouble(),
        "pitch" to current.playbackParameters.pitch.toDouble(),
        "loopEnabled" to loopEnabled,
        "loopStartMs" to loopStartMs,
        "loopEndMs" to loopEndMs,
        "loopCount" to loopCount,
        "loopEpoch" to loopEpoch,
        "loopEventsAvailable" to true,
        )
    }

    private fun releasePlayer() {
        val previous = player
        player = null
        previous?.release()
        mediaUri = null
        originalDurationMs = -1
        loopStartMs = -1
        loopEndMs = -1
        loopEnabled = false
        beginLoopEpoch()
        loopMediaItemId = null
        interruptionRevision = 0
        interruptionReason = ""
    }

    fun close() {
        channel.setMethodCallHandler(null)
        releasePlayer()
    }
}
