package com.example.transpose_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

/**
 * Keeps the song going with the app in the background, the way Spotify's own
 * app does: a media notification (title, artist, previous / play-pause /
 * next) and the same controls on the lock screen. The sound itself comes from
 * the app's pages; this service only keeps the app alive and shows the
 * controls, whose taps go back to the Dart side through [listener].
 */
class BackgroundPlaybackService : Service() {
    private var session: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "A tocar", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Controlos da música que está a tocar"
                    setShowBadge(false)
                },
            )
        }
        session = MediaSession(this, "Transpono").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onSkipToNext() = send("next")
                override fun onSkipToPrevious() = send("previous")
                override fun onSeekTo(pos: Long) = send("seek:$pos")
                override fun onStop() = send("pause")
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra(EXTRA_ACTION)?.let { send(it) }
        refresh()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        session?.isActive = false
        session?.release()
        session = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun send(action: String) {
        listener?.invoke(action)
    }

    private fun button(action: String, icon: Int, title: String, code: Int): Notification.Action {
        val intent = Intent(this, BackgroundPlaybackService::class.java).putExtra(EXTRA_ACTION, action)
        val pending = PendingIntent.getService(
            this, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(this, icon), title, pending,
        ).build()
    }

    fun refresh() {
        val session = session ?: return
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
                .build(),
        )
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_SEEK_TO,
                )
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    position,
                    if (playing) 1f else 0f,
                )
                .build(),
        )
        val open = PendingIntent.getActivity(
            this, 10,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title.ifBlank { "Transpono" })
            .setContentText(artist)
            .setContentIntent(open)
            .setOngoing(playing)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(button("previous", android.R.drawable.ic_media_previous, "Anterior", 11))
            .addAction(
                if (playing) button("pause", android.R.drawable.ic_media_pause, "Pausar", 12)
                else button("play", android.R.drawable.ic_media_play, "Reproduzir", 13),
            )
            .addAction(button("next", android.R.drawable.ic_media_next, "Seguinte", 14))
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(ID, notification)
        }
    }

    companion object {
        private const val CHANNEL = "transpono_playback"
        private const val ID = 4711
        private const val EXTRA_ACTION = "action"

        /** Taps on the notification or the lock screen go to the Dart side. */
        var listener: ((String) -> Unit)? = null

        private var instance: BackgroundPlaybackService? = null
        private var title = ""
        private var artist = ""
        private var playing = false
        private var position = 0L
        private var duration = 0L

        fun update(
            context: Context,
            title: String,
            artist: String,
            playing: Boolean,
            position: Long,
            duration: Long,
        ) {
            this.title = title
            this.artist = artist
            this.playing = playing
            this.position = position
            this.duration = duration
            val running = instance
            if (running != null) {
                running.refresh()
                return
            }
            // Only started while something plays (the app is then in front).
            if (!playing) return
            val intent = Intent(context, BackgroundPlaybackService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (_: RuntimeException) {
                // Not allowed right now (app in the background): tried again
                // at the next update.
            }
        }

        fun stop(context: Context) {
            if (instance == null) return
            context.stopService(Intent(context, BackgroundPlaybackService::class.java))
        }
    }
}
