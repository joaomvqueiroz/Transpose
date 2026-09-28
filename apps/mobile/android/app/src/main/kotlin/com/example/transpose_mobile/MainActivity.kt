package com.example.transpose_mobile

import android.media.AudioManager
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var processingProbe: Media3ChannelPlayer? = null
    private var audioPlayer: Media3ChannelPlayer? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Keep physical volume keys assigned to media, including while paused.
        volumeControlStream = AudioManager.STREAM_MUSIC
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
        processingProbe?.close()
        processingProbe = null
        audioPlayer?.close()
        audioPlayer = null
        widgetChannel?.setMethodCallHandler(null)
        widgetChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
