import 'package:flutter_test/flutter_test.dart';
import 'package:fuehrerschein_quiz/data/user_data.dart';
import 'package:fuehrerschein_quiz/services/update_service.dart';

void main() {
  group('UserData.mergeFrom', () {
    test('vereinigt Antworten zweier Geräte ohne Duplikate', () {
      final phone = UserData(events: {
        'phone': [const AnswerEvent(1, 100, true, 0), const AnswerEvent(2, 110, false, 0)],
      });
      final pc = UserData(events: {
        'pc': [const AnswerEvent(3, 105, true, 0)],
        'phone': [const AnswerEvent(1, 100, true, 0)],
      });
      expect(phone.mergeFrom(pc), isTrue);
      expect(phone.totalEvents, 3);
      expect(phone.mergeFrom(pc), isFalse, reason: 'zweites Zusammenführen ändert nichts');

      expect(pc.mergeFrom(phone), isTrue);
      expect(pc.totalEvents, 3);
    });

    test('neuester Zeitstempel gewinnt bei Favoriten, Notizen und Einstellungen', () {
      final a = UserData(favorites: {1: (10, true)}, notes: {1: (10, 'alt')}, settingsTs: 5);
      final b = UserData(favorites: {1: (20, false)}, notes: {1: (5, 'älter')}, settingsTs: 9)
        ..settings.dailyGoal = 99;
      a.mergeFrom(b);
      expect(a.favorites[1], (20, false));
      expect(a.notes[1], (10, 'alt'));
      expect(a.settings.dailyGoal, 99);
    });

    test('Zurücksetzen wird übertragen und entfernt alte Antworten', () {
      final a = UserData(events: {
        'x': [const AnswerEvent(1, 100, true, 0), const AnswerEvent(2, 300, true, 0)],
      });
      final b = UserData(resetTs: 200);
      a.mergeFrom(b);
      expect(a.totalEvents, 1);
      expect(a.events['x']!.single.qid, 2);
    });

    test('JSON hin und zurück', () {
      final a = UserData(
        events: {'x': [const AnswerEvent(21810, 1700000000, true, 1)]},
        favorites: {21810: (1, true)},
        notes: {21811: (2, 'Eselsbrücke')},
      );
      final b = UserData.fromJson(a.toJson());
      expect(b.totalEvents, 1);
      expect(b.events['x']!.single.mode, 1);
      expect(b.favorites[21810], (1, true));
      expect(b.notes[21811]!.$2, 'Eselsbrücke');
    });
  });

  test('Versionsvergleich', () {
    expect(compareVersions('1.2.10', '1.2.9'), greaterThan(0));
    expect(compareVersions('v1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0', '1.1.0'), lessThan(0));
    expect(compareVersions('2.0', '1.9.9'), greaterThan(0));
  });
}
