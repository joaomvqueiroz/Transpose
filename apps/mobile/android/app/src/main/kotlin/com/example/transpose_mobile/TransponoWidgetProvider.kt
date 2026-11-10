package com.example.transpose_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** Four launcher sizes share the same acknowledged player snapshot. */
abstract class TransponoWidgetProvider(private val layout: Int) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, render(context, it)) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle,
    ) {
        manager.updateAppWidget(appWidgetId, render(context, appWidgetId))
    }

    private fun render(context: Context, widgetId: Int): RemoteViews {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, layout)
        val title = preferences.getString("title", "Transpono") ?: "Transpono"
        val active = preferences.getBoolean("active", false)
        views.setTextViewText(R.id.w_title, title)
        views.setTextViewText(
            R.id.w_subtitle,
            if (active) preferences.getString("subtitle", "") ?: ""
            else "Abra o Transpono para escolher uma música",
        )
        views.setTextViewText(R.id.w_position, preferences.getString("position", "0:00"))
        views.setTextViewText(R.id.w_duration, preferences.getString("duration", "0:00"))
        views.setProgressBar(R.id.w_progress, 100, preferences.getInt("progress", 0), false)
        views.setTextViewText(R.id.w_play, if (active && preferences.getBoolean("playing", false)) "Ⅱ" else "▶")
        val pitch = preferences.getInt("pitch", 0)
        views.setTextViewText(R.id.w_pitch, if (layout == R.layout.widget_small) "${if (pitch == 0) "Original" else "Tom"} · ${if (pitch > 0) "+" else ""}$pitch st"
            else "${if (pitch > 0) "+" else ""}$pitch st")
        views.setOnClickPendingIntent(R.id.w_root, action(context, widgetId, "open"))
        views.setOnClickPendingIntent(R.id.w_play, action(context, widgetId, "play"))
        views.setOnClickPendingIntent(R.id.w_back, action(context, widgetId, "back"))
        views.setOnClickPendingIntent(R.id.w_forward, action(context, widgetId, "forward"))
        if (layout != R.layout.widget_small) {
            views.setOnClickPendingIntent(R.id.w_pitch_minus, action(context, widgetId, "pitchMinus"))
            views.setOnClickPendingIntent(R.id.w_pitch_plus, action(context, widgetId, "pitchPlus"))
        }
        if (layout == R.layout.widget_large || layout == R.layout.widget_cockpit) {
            views.setTextViewText(R.id.w_chord, preferences.getString("chord", "Abra a cifra no app"))
            views.setTextViewText(R.id.w_loop, preferences.getString("loop", "A–B: não marcado"))
            views.setOnClickPendingIntent(R.id.w_chord, action(context, widgetId, "chord"))
            views.setOnClickPendingIntent(R.id.w_loop, action(context, widgetId, "loop"))
        }
        if (layout == R.layout.widget_cockpit) {
            views.setOnClickPendingIntent(R.id.w_tuner, action(context, widgetId, "tuner"))
            views.setTextViewText(R.id.w_speed, preferences.getString("speed", "1.00x"))
        }
        return views
    }

    companion object {
        const val EXTRA_ACTION = "transpono_widget_action"
        private const val PREFS = "transpono_widget_state"
        private val providers = listOf(
            TransponoWidgetSmall::class.java,
            TransponoWidgetMedium::class.java,
            TransponoWidgetLarge::class.java,
            TransponoWidgetCockpit::class.java,
        )

        fun saveState(context: Context, state: Map<*, *>) {
            val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            listOf("title", "subtitle", "position", "duration", "chord", "loop", "speed").forEach { key ->
                edit.putString(key, state[key] as? String ?: "")
            }
            edit.putBoolean("active", state["active"] == true)
            edit.putBoolean("playing", state["playing"] == true)
            edit.putInt("pitch", (state["pitch"] as? Number)?.toInt() ?: 0)
            edit.putInt("progress", ((state["progress"] as? Number)?.toInt() ?: 0).coerceIn(0, 100))
            edit.apply()
            TransponoWidgetNow.refresh(context, state["art"] as? String ?: "")
            val manager = AppWidgetManager.getInstance(context)
            providers.forEach { provider ->
                val component = ComponentName(context, provider)
                val ids = manager.getAppWidgetIds(component)
                if (ids.isNotEmpty()) {
                    val instance = provider.getDeclaredConstructor().newInstance()
                    instance.onUpdate(context, manager, ids)
                }
            }
        }

        private fun action(context: Context, widgetId: Int, name: String): PendingIntent {
            val actionCode = listOf("open", "play", "back", "forward", "pitchMinus", "pitchPlus", "chord", "loop", "tuner")
                .indexOf(name).coerceAtLeast(0)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_ACTION, name)
            }
            return PendingIntent.getActivity(
                context, widgetId * 16 + actionCode,
                intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

class TransponoWidgetSmall : TransponoWidgetProvider(R.layout.widget_small)
class TransponoWidgetMedium : TransponoWidgetProvider(R.layout.widget_medium)
class TransponoWidgetLarge : TransponoWidgetProvider(R.layout.widget_large)
class TransponoWidgetCockpit : TransponoWidgetProvider(R.layout.widget_cockpit)
