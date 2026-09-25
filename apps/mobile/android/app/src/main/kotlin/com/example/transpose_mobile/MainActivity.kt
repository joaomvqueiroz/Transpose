package com.example.transpose_mobile

import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var processingProbe: Media3ChannelPlayer? = null
    private var audioPlayer: Media3ChannelPlayer? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        processingProbe?.close()
        processingProbe = null
        audioPlayer?.close()
        audioPlayer = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
