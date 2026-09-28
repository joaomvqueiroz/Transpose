package com.example.transpose_mobile

import android.media.AudioManager
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import android.view.WindowManager
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
        stemMessenger = flutterEngine.dartExecutor.binaryMessenger
        stems = StemEngine.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(bandNoisy, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(bandNoisy, filter)
        bandNoisyRegistered = true
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
}
