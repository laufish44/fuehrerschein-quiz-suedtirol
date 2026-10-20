import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';

/// Tägliche Lern-Erinnerung (Android und Windows).
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows);

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: AppConfig.appName,
            appUserModelId: 'io.github.laufish44.FuehrerscheinQuiz',
            guid: '6c1d7b3e-4f0a-4d2b-9a57-2f1e8c9d4b61',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications nicht verfügbar: $e');
    }
  }

  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminder',
      'Lern-Erinnerung',
      channelDescription: 'Tägliche Erinnerung ans Lernen',
      importance: Importance.defaultImportance,
    ),
    windows: WindowsNotificationDetails(),
  );

  /// Plant die tägliche Erinnerung neu (oder löscht sie, wenn [enabled] false ist).
  static Future<void> schedule({
    required bool enabled,
    required int hour,
    required int minute,
    required bool italian,
    String? examDate,
  }) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      for (var i = 0; i < 8; i++) {
        await _plugin.cancel(id: 100 + i);
      }
    } catch (_) {}
    if (!enabled) return;

    final title = italian ? 'È ora di studiare! 🚗' : 'Zeit zum Lernen! 🚗';
    String body = italian
        ? 'Qualche domanda al giorno e la patente è tua.'
        : 'Ein paar Fragen am Tag und der Führerschein gehört dir.';
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin.zonedSchedule(
          id: 100,
          title: title,
          body: body,
          scheduledDate: first,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        // Windows kennt keine Wiederholung: die nächsten 7 Tage einzeln planen
        // (wird bei jedem App-Start erneuert).
        for (var i = 0; i < 7; i++) {
          final day = first.add(Duration(days: i));
          var text = body;
          if (examDate != null) {
            final exam = DateTime.tryParse(examDate);
            if (exam != null) {
              final left = DateTime(exam.year, exam.month, exam.day)
                  .difference(DateTime(day.year, day.month, day.day))
                  .inDays;
              if (left >= 0) {
                text = italian ? 'Ancora $left giorni all\'esame.' : 'Noch $left Tage bis zur Prüfung.';
              }
            }
          }
          await _plugin.zonedSchedule(
            id: 100 + i,
            title: title,
            body: text,
            scheduledDate: day,
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      debugPrint('Erinnerung konnte nicht geplant werden: $e');
    }
  }
}
