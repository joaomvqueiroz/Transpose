package com.example.transpose_mobile

import android.media.AudioManager
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.graphics.drawable.Icon
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

class MainActivity : FlutterActivity() {
    private var processingProbe: Media3ChannelPlayer? = null
    private var audioPlayer: Media3ChannelPlayer? = null
    private var bandAudio: BandAudioEngine? = null
    private var qaBandAcoustic: QaBandAcousticProbe? = null
    private var qaPhoneRhythm: PhoneRhythmFeatureCapture? = null
    private var stems: StemEngine? = null
    private var stemMessenger: BinaryMessenger? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null
    private val bandNoisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) bandAudio?.interrupt()
        }
    }
    private var bandNoisyRegistered = false

    // Picture-in-picture: while a YouTube video plays, leaving the app shows
    // it in the system's small window (the Dart side draws only the video).
    private var pipChannel: MethodChannel? = null
    private var videoPlaying = false

    // The small window's own buttons (back 10 s, play or pause, forward
    // 10 s): each is a broadcast that goes on to the Dart side.
    private val pipButtons = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val name = intent?.getStringExtra(PIP_BUTTON) ?: return
            pipChannel?.invokeMethod("pipAction", name)
        }
    }
    private var pipButtonsRegistered = false
    private var inPip = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (packageName == "com.example.transpose_mobile.qa") {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        // Keep physical volume keys assigned to media, including while paused.
        volumeControlStream = AudioManager.STREAM_MUSIC
        bandAudio = BandAudioEngine(
            flutterEngine.dartExecutor.binaryMessenger,
            qaAcousticEnabled = packageName == "com.example.transpose_mobile.qa",
        )
        qaBandAcoustic = QaBandAcousticProbe.attach(
            applicationContext, flutterEngine.dartExecutor.binaryMessenger,
        )
        qaPhoneRhythm = PhoneRhythmFeatureCapture.attach(
            applicationContext, flutterEngine.dartExecutor.binaryMessenger,
        )
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "transpono/pip").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "setVideoPlaying") {
                    videoPlaying = call.arguments == true
                    // Also on older systems: the play/pause button follows.
                    if (Build.VERSION.SDK_INT >= 26) {
                        try {
                            setPictureInPictureParams(pipParams())
                        } catch (_: RuntimeException) {
                            // Refused right now: tried again at the next change.
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
        stemMessenger = flutterEngine.dartExecutor.binaryMessenger
        stems = StemEngine.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(bandNoisy, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(bandNoisy, filter)
        bandNoisyRegistered = true
        val pipFilter = IntentFilter(PIP_ACTION)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(pipButtons, pipFilter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(pipButtons, pipFilter)
        pipButtonsRegistered = true
        processingProbe = Media3ChannelPlayer(
            this, flutterEngine.dartExecutor.binaryMessenger,
            "transpose/native_processing_probe",
        )
        audioPlayer = Media3ChannelPlayer(
            this, flutterEngine.dartExecutor.binaryMessenger,
            "transpose/native_audio_player",
        )
        pendingWidgetAction = intent?.getStringExtra(TransponoWidgetProvider.EXTRA_ACTION)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "transpose/home_widgets")
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val state = call.arguments as? Map<*, *>
                    if (state == null) result.error("INVALID_STATE", "Missing widget state", null)
                    else {
                        TransponoWidgetProvider.saveState(this, state)
                        result.success(null)
                    }
                }
                "takeAction" -> {
                    result.success(pendingWidgetAction)
                    pendingWidgetAction = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(TransponoWidgetProvider.EXTRA_ACTION) ?: return
        if (widgetChannel == null) pendingWidgetAction = action
        else widgetChannel?.invokeMethod("action", action)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (bandNoisyRegistered) { unregisterReceiver(bandNoisy); bandNoisyRegistered = false }
        if (pipButtonsRegistered) { unregisterReceiver(pipButtons); pipButtonsRegistered = false }
        bandAudio?.close()
        bandAudio = null
        qaBandAcoustic?.close()
        qaBandAcoustic = null
        qaPhoneRhythm?.close()
        qaPhoneRhythm = null
        stems?.close(flutterEngine.dartExecutor.binaryMessenger)
        stems = null
        stemMessenger = null
        processingProbe?.close()
        processingProbe = null
        audioPlayer?.close()
        audioPlayer = null
        widgetChannel?.setMethodCallHandler(null)
        widgetChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPause() {
        bandAudio?.interrupt()
        qaPhoneRhythm?.cancel()
        stems?.cancelForLifecycle(stemMessenger)
        super.onPause()
    }

    @RequiresApi(26)
    private fun pipButton(name: String, icon: Int, title: String, code: Int): RemoteAction {
        val intent = Intent(PIP_ACTION).setPackage(packageName).putExtra(PIP_BUTTON, name)
        val pending = PendingIntent.getBroadcast(
            this, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return RemoteAction(Icon.createWithResource(this, icon), title, title, pending)
    }

    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        // The buttons are an extra: if the system refuses them, the small
        // window must still open.
        try {
            builder.setActions(
                listOf(
                    pipButton("back", android.R.drawable.ic_media_rew, "Voltar 10 segundos", 1),
                    if (videoPlaying) pipButton("play", android.R.drawable.ic_media_pause, "Pausar", 2)
                    else pipButton("play", android.R.drawable.ic_media_play, "Reproduzir", 3),
                    pipButton("forward", android.R.drawable.ic_media_ff, "Avançar 10 segundos", 4),
                ),
            )
        } catch (_: RuntimeException) {
        }
        if (Build.VERSION.SDK_INT >= 31) builder.setAutoEnterEnabled(videoPlaying || inPip)
        return builder.build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12+ enters by itself (setAutoEnterEnabled); older versions here.
        if (videoPlaying && Build.VERSION.SDK_INT in 26..30) {
            try {
                enterPictureInPictureMode(pipParams())
            } catch (_: IllegalStateException) {
                // Not allowed right now: leave normally.
            }
        }
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        this.inPip = inPip
        pipChannel?.invokeMethod("pipChanged", inPip)
    }

    companion object {
        private const val PIP_ACTION = "com.example.transpose_mobile.PIP_BUTTON"
        private const val PIP_BUTTON = "name"
    }
}
