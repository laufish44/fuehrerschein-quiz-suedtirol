package io.github.laufish44.fuehrerschein_quiz

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Startbildschirm-Widget: Tagesziel, Serie, Tage bis zur Prüfung, Bestehenschance. */
class LernWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.lern_widget).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
                setTextViewText(R.id.widget_title, widgetData.getString("title", null) ?: "Führerschein Quiz")
                setTextViewText(R.id.widget_goal, widgetData.getString("goalText", null) ?: "Öffnen zum Lernen")
                val done = widgetData.getInt("today", 0)
                val goal = widgetData.getInt("goal", 0)
                setProgressBar(R.id.widget_progress, if (goal > 0) goal else 1, minOf(done, if (goal > 0) goal else 1), false)
                setTextViewText(R.id.widget_streak, widgetData.getString("streakText", null) ?: "")
                setTextViewText(R.id.widget_exam, widgetData.getString("examText", null) ?: "")
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
