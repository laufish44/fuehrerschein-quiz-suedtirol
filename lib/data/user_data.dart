import 'dart:math';

/// Art, wie eine Antwort gegeben wurde.
class AnswerMode {
  static const practice = 0;
  static const exam = 1;
}

int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String randomId([int length = 12]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Eine gegebene Antwort. Wird kompakt als [qid, ts, correct, mode] gespeichert.
class AnswerEvent {
  final int qid;
  final int ts;
  final bool correct;
  final int mode;

  const AnswerEvent(this.qid, this.ts, this.correct, this.mode);

  List<int> toJson() => [qid, ts, correct ? 1 : 0, mode];

  factory AnswerEvent.fromJson(List<dynamic> j) =>
      AnswerEvent(j[0] as int, j[1] as int, j[2] == 1, j.length > 3 ? j[3] as int : 0);

  String get key => '$qid:$ts:$mode:${correct ? 1 : 0}';
}

class ExamRecord {
  final String id;
  final int start;
  final int durationSec;
  final int limitSec;
  final bool official;
  final int maxErrors;
  final List<int> qids;

  /// 1 = "richtig" gewählt, 0 = "falsch" gewählt, -1 = nicht beantwortet.
  final List<int> answers;

  ExamRecord({
    required this.id,
    required this.start,
    required this.durationSec,
    required this.limitSec,
    required this.official,
    required this.maxErrors,
    required this.qids,
    required this.answers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start,
        'dur': durationSec,
        'limit': limitSec,
        'off': official,
        'maxE': maxErrors,
        'q': qids,
        'a': answers,
      };

  factory ExamRecord.fromJson(Map<String, dynamic> j) => ExamRecord(
        id: j['id'] as String,
        start: j['start'] as int,
        durationSec: j['dur'] as int,
        limitSec: j['limit'] as int,
        official: j['off'] as bool,
        maxErrors: j['maxE'] as int,
        qids: [for (final x in j['q'] as List) x as int],
        answers: [for (final x in j['a'] as List) x as int],
      );
}

/// Einstellungen, die zwischen Geräten synchronisiert werden.
class SyncedSettings {
  String uiLanguage; // 'de' oder 'it'
  String questionLanguage; // 'de' oder 'it'
  bool showSecondLanguage;
  bool practiceImmediateFeedback;
  bool examImmediateFeedback;
  int dailyGoal;
  String? examDate; // yyyy-mm-dd
  int learnedStreak; // so oft in Folge richtig = "gelernt"
  int errorClearStreak; // so oft in Folge richtig = raus aus "Meine Fehler"
  String aiService; // chatgpt | claude | perplexity | gemini
  int sessionSize;

  SyncedSettings({
    this.uiLanguage = 'de',
    this.questionLanguage = 'de',
    this.showSecondLanguage = false,
    this.practiceImmediateFeedback = true,
    this.examImmediateFeedback = false,
    this.dailyGoal = 60,
    this.examDate,
    this.learnedStreak = 3,
    this.errorClearStreak = 2,
    this.aiService = 'chatgpt',
    this.sessionSize = 20,
  });

  Map<String, dynamic> toJson() => {
        'uiLanguage': uiLanguage,
        'questionLanguage': questionLanguage,
        'showSecondLanguage': showSecondLanguage,
        'practiceImmediateFeedback': practiceImmediateFeedback,
        'examImmediateFeedback': examImmediateFeedback,
        'dailyGoal': dailyGoal,
        'examDate': examDate,
        'learnedStreak': learnedStreak,
        'errorClearStreak': errorClearStreak,
        'aiService': aiService,
        'sessionSize': sessionSize,
      };

  factory SyncedSettings.fromJson(Map<String, dynamic> j) {
    final d = SyncedSettings();
    return SyncedSettings(
      uiLanguage: j['uiLanguage'] as String? ?? d.uiLanguage,
      questionLanguage: j['questionLanguage'] as String? ?? d.questionLanguage,
      showSecondLanguage: j['showSecondLanguage'] as bool? ?? d.showSecondLanguage,
      practiceImmediateFeedback: j['practiceImmediateFeedback'] as bool? ?? d.practiceImmediateFeedback,
      examImmediateFeedback: j['examImmediateFeedback'] as bool? ?? d.examImmediateFeedback,
      dailyGoal: j['dailyGoal'] as int? ?? d.dailyGoal,
      examDate: j['examDate'] as String?,
      learnedStreak: j['learnedStreak'] as int? ?? d.learnedStreak,
      errorClearStreak: j['errorClearStreak'] as int? ?? d.errorClearStreak,
      aiService: j['aiService'] as String? ?? d.aiService,
      sessionSize: j['sessionSize'] as int? ?? d.sessionSize,
    );
  }
}

/// Der gesamte Lernstand. Ist so aufgebaut, dass zwei Stände (z. B. Handy und PC)
/// ohne Datenverlust zusammengeführt werden können:
/// - Antworten sind pro Gerät nur angehängt und werden vereinigt,
/// - Prüfungen werden über ihre ID vereinigt,
/// - Favoriten, Notizen und Einstellungen: der neueste Zeitstempel gewinnt.
class UserData {
  Map<String, List<AnswerEvent>> events;
  Map<String, ExamRecord> exams;
  Map<String, Map<String, int>> studySeconds; // Gerät -> Tag -> Sekunden
  Map<int, (int, bool)> favorites; // qid -> (ts, aktiv)
  Map<int, (int, String)> notes; // qid -> (ts, Text; leer = gelöscht)
  SyncedSettings settings;
  int settingsTs;
  int resetTs;

  UserData({
    Map<String, List<AnswerEvent>>? events,
    Map<String, ExamRecord>? exams,
    Map<String, Map<String, int>>? studySeconds,
    Map<int, (int, bool)>? favorites,
    Map<int, (int, String)>? notes,
    SyncedSettings? settings,
    this.settingsTs = 0,
    this.resetTs = 0,
  })  : events = events ?? {},
        exams = exams ?? {},
        studySeconds = studySeconds ?? {},
        favorites = favorites ?? {},
        notes = notes ?? {},
        settings = settings ?? SyncedSettings();

  Map<String, dynamic> toJson() => {
        'format': 1,
        'events': {for (final e in events.entries) e.key: [for (final ev in e.value) ev.toJson()]},
        'exams': [for (final x in exams.values) x.toJson()],
        'study': studySeconds,
        'fav': {for (final e in favorites.entries) '${e.key}': [e.value.$1, e.value.$2 ? 1 : 0]},
        'notes': {for (final e in notes.entries) '${e.key}': [e.value.$1, e.value.$2]},
        'settings': settings.toJson(),
        'settingsTs': settingsTs,
        'resetTs': resetTs,
      };

  factory UserData.fromJson(Map<String, dynamic> j) {
    return UserData(
      events: {
        for (final e in ((j['events'] as Map?) ?? const {}).entries)
          e.key as String: [for (final ev in e.value as List) AnswerEvent.fromJson(ev as List)],
      },
      exams: {
        for (final x in (j['exams'] as List?) ?? const [])
          (x as Map<String, dynamic>)['id'] as String: ExamRecord.fromJson(x),
      },
      studySeconds: {
        for (final e in ((j['study'] as Map?) ?? const {}).entries)
          e.key as String: {for (final d in (e.value as Map).entries) d.key as String: d.value as int},
      },
      favorites: {
        for (final e in ((j['fav'] as Map?) ?? const {}).entries)
          int.parse(e.key as String): ((e.value as List)[0] as int, (e.value as List)[1] == 1),
      },
      notes: {
        for (final e in ((j['notes'] as Map?) ?? const {}).entries)
          int.parse(e.key as String): ((e.value as List)[0] as int, (e.value as List)[1] as String),
      },
      settings: SyncedSettings.fromJson((j['settings'] as Map<String, dynamic>?) ?? const {}),
      settingsTs: j['settingsTs'] as int? ?? 0,
      resetTs: j['resetTs'] as int? ?? 0,
    );
  }

  int get totalEvents => events.values.fold(0, (s, l) => s + l.length);

  /// Führt einen anderen Stand in diesen ein. Gibt true zurück, wenn sich etwas geändert hat.
  bool mergeFrom(UserData other) {
    var changed = false;

    for (final entry in other.events.entries) {
      final mine = events[entry.key] ??= [];
      final keys = {for (final e in mine) e.key};
      var added = false;
      for (final e in entry.value) {
        if (keys.add(e.key)) {
          mine.add(e);
          added = true;
        }
      }
      if (added) {
        mine.sort((a, b) => a.ts.compareTo(b.ts));
        changed = true;
      }
    }

    for (final x in other.exams.entries) {
      if (!exams.containsKey(x.key)) {
        exams[x.key] = x.value;
        changed = true;
      }
    }

    for (final dev in other.studySeconds.entries) {
      final mine = studySeconds[dev.key] ??= {};
      for (final d in dev.value.entries) {
        if ((mine[d.key] ?? 0) < d.value) {
          mine[d.key] = d.value;
          changed = true;
        }
      }
    }

    for (final f in other.favorites.entries) {
      final mine = favorites[f.key];
      if (mine == null || mine.$1 < f.value.$1) {
        favorites[f.key] = f.value;
        changed = true;
      }
    }

    for (final n in other.notes.entries) {
      final mine = notes[n.key];
      if (mine == null || mine.$1 < n.value.$1) {
        notes[n.key] = n.value;
        changed = true;
      }
    }

    if (other.settingsTs > settingsTs) {
      settings = SyncedSettings.fromJson(other.settings.toJson());
      settingsTs = other.settingsTs;
      changed = true;
    }

    if (other.resetTs > resetTs) {
      resetTs = other.resetTs;
      changed = true;
    }
    if (prune()) changed = true;
    return changed;
  }

  /// Entfernt alles, was vor dem letzten "Fortschritt zurücksetzen" lag.
  bool prune() {
    if (resetTs == 0) return false;
    var changed = false;
    for (final list in events.values) {
      final before = list.length;
      list.removeWhere((e) => e.ts < resetTs);
      if (list.length != before) changed = true;
    }
    final beforeExams = exams.length;
    exams.removeWhere((_, x) => x.start < resetTs);
    if (exams.length != beforeExams) changed = true;
    if (studySeconds.isNotEmpty) {
      final resetDay = dayKey(DateTime.fromMillisecondsSinceEpoch(resetTs * 1000));
      for (final m in studySeconds.values) {
        final before = m.length;
        m.removeWhere((day, _) => day.compareTo(resetDay) < 0);
        if (m.length != before) changed = true;
      }
    }
    return changed;
  }
}
