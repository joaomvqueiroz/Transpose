package com.example.transpose_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Opens the app with a widget action; every action has its own request code. */
private fun widgetIntent(context: Context, widgetId: Int, name: String, code: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(TransponoWidgetProvider.EXTRA_ACTION, name)
    }
    return PendingIntent.getActivity(
        context, 1_000_000 + widgetId * 32 + code,
        intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/**
 * Search widget, in the shape of the YouTube one: a search pill and a row of
 * shortcuts, here one per listening source.
 */
class TransponoWidgetSearch : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_search)
            views.setOnClickPendingIntent(R.id.ws_search, widgetIntent(context, id, "search", 0))
            views.setOnClickPendingIntent(R.id.ws_youtube, widgetIntent(context, id, "source:youtube", 1))
            views.setOnClickPendingIntent(R.id.ws_music, widgetIntent(context, id, "source:youtubeMusic", 2))
            views.setOnClickPendingIntent(R.id.ws_soundcloud, widgetIntent(context, id, "source:soundCloud", 3))
            views.setOnClickPendingIntent(R.id.ws_spotify, widgetIntent(context, id, "source:spotify", 4))
            manager.updateAppWidget(id, views)
        }
    }
}

/**
 * "Now playing" widget, in the shape of the Spotify and YouTube Music ones:
 * the cover on the left, title and source, and back / play / forward.
 */
class TransponoWidgetNow : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, render(context, it)) }
    }

    companion object {
        private const val PREFS = "transpono_widget_state"
        private const val ART_FILE = "widget_art.jpg"

        private fun render(context: Context, widgetId: Int): RemoteViews {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_now)
            val active = preferences.getBoolean("active", false)
            views.setTextViewText(R.id.wn_title, preferences.getString("title", "Transpono") ?: "Transpono")
            views.setTextViewText(
                R.id.wn_subtitle,
                if (active) preferences.getString("subtitle", "") ?: ""
                else "Abra o Transpono para escolher uma música",
            )
            views.setImageViewResource(
                R.id.wn_play,
                if (active && preferences.getBoolean("playing", false)) R.drawable.widget_ic_pause
                else R.drawable.widget_ic_play,
            )
            val art = preferences.getString("art", "") ?: ""
            val cover = if (active && art.isNotEmpty() && art == preferences.getString("artShown", "")) {
                cover(context)
            } else {
                null
            }
            if (cover != null) views.setImageViewBitmap(R.id.wn_art, cover)
            else views.setImageViewResource(R.id.wn_art, R.mipmap.ic_launcher)
            views.setOnClickPendingIntent(R.id.wn_root, widgetIntent(context, widgetId, "open", 8))
            views.setOnClickPendingIntent(R.id.wn_back, widgetIntent(context, widgetId, "back", 9))
            views.setOnClickPendingIntent(R.id.wn_play, widgetIntent(context, widgetId, "play", 10))
            views.setOnClickPendingIntent(R.id.wn_forward, widgetIntent(context, widgetId, "forward", 11))
            return views
        }

        private fun cover(context: Context): Bitmap? {
            val file = File(context.cacheDir, ART_FILE)
            if (!file.exists()) return null
            return try { BitmapFactory.decodeFile(file.path) } catch (_: Throwable) { null }
        }

        private fun redraw(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TransponoWidgetNow::class.java))
            ids.forEach { manager.updateAppWidget(it, render(context, it)) }
        }

        /** Called after the player state was saved; fetches a new cover off the main thread. */
        fun refresh(context: Context, art: String) {
            val app = context.applicationContext
            val preferences = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val shown = preferences.getString("artShown", "")
            preferences.edit().putString("art", art).apply()
            redraw(app)
            // Only the video thumbnails of YouTube, over HTTPS.
            if (art == shown || !art.startsWith("https://i.ytimg.com/vi/")) return
            Thread {
                try {
                    val connection = URL(art).openConnection() as HttpURLConnection
                    connection.connectTimeout = 8000
                    connection.readTimeout = 8000
                    val full = connection.inputStream.use { BitmapFactory.decodeStream(it) } ?: return@Thread
                    val side = minOf(full.width, full.height)
                    val square = Bitmap.createBitmap(
                        full, (full.width - side) / 2, (full.height - side) / 2, side, side,
                    )
                    File(app.cacheDir, ART_FILE).outputStream().use {
                        square.compress(Bitmap.CompressFormat.JPEG, 88, it)
                    }
                    preferences.edit().putString("artShown", art).apply()
                    redraw(app)
                } catch (_: Throwable) {
                    // No network: the app icon stays as the cover.
                }
            }.start()
        }
    }
}
