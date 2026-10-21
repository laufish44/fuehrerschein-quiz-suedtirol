import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../app_state.dart';
import '../data/study_features.dart';

/// Aktualisiert das Android-Startbildschirm-Widget (Tagesziel, Serie, Prüfungstermin).
class WidgetService {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> update(AppState app) async {
    if (!supported) return;
    try {
      final p = app.progress;
      final it = app.italianUi;
      final plan = studyPlan(p, app.bank);
      final goal = plan != null && !plan.examPassed ? plan.perDay : app.settings.dailyGoal;
      final today = p.today().answered;
      final streak = p.dayStreak;
      final pass = (p.passProbability() * 100).round();
      await HomeWidget.saveWidgetData<String>('title', it ? 'Quiz Patente' : 'Führerschein Quiz');
      await HomeWidget.saveWidgetData<int>('today', today);
      await HomeWidget.saveWidgetData<int>('goal', goal);
      await HomeWidget.saveWidgetData<String>(
        'goalText',
        today >= goal ? (it ? 'Obiettivo raggiunto ✓' : 'Tagesziel geschafft ✓') : (it ? 'Oggi $today / $goal' : 'Heute $today / $goal'),
      );
      await HomeWidget.saveWidgetData<String>(
        'streakText',
        it ? '🔥 $streak ${streak == 1 ? 'giorno' : 'giorni'} · $pass % promozione' : '🔥 $streak ${streak == 1 ? 'Tag' : 'Tage'} · $pass % Bestehen',
      );
      await HomeWidget.saveWidgetData<String>(
        'examText',
        plan == null
            ? (it ? 'Imposta la data dell\'esame' : 'Prüfungstermin festlegen')
            : plan.examPassed
                ? ''
                : (it ? 'Esame tra ${plan.daysLeft - 1} giorni' : 'Prüfung in ${plan.daysLeft - 1} Tagen'),
      );
      await HomeWidget.updateWidget(androidName: 'LernWidgetProvider');
    } catch (_) {
      // Ohne Widget auf dem Startbildschirm ist das egal.
    }
  }
}
