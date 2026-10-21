import 'dart:math';

import 'progress.dart';
import 'question_bank.dart';
import 'user_data.dart';

// ---------- Lernplan ----------

/// Lernplan bis zum Prüfungstermin.
class StudyPlan {
  final int daysLeft; // inklusive heute
  final int remaining; // noch nicht gelernte Aussagen
  final int perDay; // empfohlene Fragen pro Tag (neue + Wiederholung)
  final int doneToday;
  final bool examPassed; // Termin liegt in der Vergangenheit

  const StudyPlan({
    required this.daysLeft,
    required this.remaining,
    required this.perDay,
    required this.doneToday,
    required this.examPassed,
  });

  /// Anteil des heutigen Pensums.
  double get todayRatio => perDay == 0 ? 1 : min(1, doneToday / perDay);

  /// Bleibt einem bei diesem Tempo am Ende noch Zeit zum Wiederholen?
  bool get tight => perDay > 250;
}

/// Rechnet aus dem Prüfungstermin aus, wie viel man pro Tag lernen sollte.
/// Ziel: alle Aussagen 2 Tage vor der Prüfung gelernt; jede braucht im Schnitt ~2,5 Antworten
/// (bis sie [SyncedSettings.learnedStreak]-mal in Folge richtig war), dazu die fälligen Wiederholungen.
StudyPlan? studyPlan(Progress p, QuestionBank bank, {DateTime? now}) {
  final exam = DateTime.tryParse(p.settings.examDate ?? '');
  if (exam == null) return null;
  final t = now ?? DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final days = DateTime(exam.year, exam.month, exam.day).difference(today).inDays;
  final remaining = bank.questions.length - p.learnedCount;
  if (days < 0) {
    return StudyPlan(daysLeft: 0, remaining: remaining, perDay: 0, doneToday: p.today().answered, examPassed: true);
  }
  final learnDays = max(1, days - 1); // die letzten Tage bleiben für Prüfungssimulationen
  final answersNeeded = remaining * 2.5;
  final review = min(60, p.dueQuestions().length ~/ max(1, min(days, 7)));
  final perDay = ((answersNeeded / learnDays) + review).ceil();
  return StudyPlan(
    daysLeft: days + 1,
    remaining: remaining,
    perDay: max(20, ((perDay + 9) ~/ 10) * 10),
    doneToday: p.today().answered,
    examPassed: false,
  );
}

// ---------- Prüfungsreif-Ampel ----------

enum Readiness { red, yellow, green }

/// Ampel für ein Kapitel: grün = sicher, gelb = fast, rot = noch Lücken.
Readiness chapterReadiness(ChapterStat cs) {
  if (cs.seenRatio >= 0.8 && cs.knowledge >= 0.85 && cs.errors <= max(1, cs.total ~/ 50)) return Readiness.green;
  if (cs.seenRatio >= 0.5 && cs.knowledge >= 0.7) return Readiness.yellow;
  return Readiness.red;
}

// ---------- Bilder-Quiz ----------

class ImageQuizItem {
  final QuestionGroup group;
  final String image;
  final List<Question> options; // eine richtige Aussage zu diesem Bild + Aussagen zu anderen Bildern
  final Question correct;
  const ImageQuizItem(this.group, this.image, this.options, this.correct);
}

Set<String> _words(String s) => {
      for (final w in s.toLowerCase().split(RegExp(r'[^a-zäöüß0-9]+')))
        if (w.length >= 4) w,
    };

double _similar(String a, String b) {
  final x = _words(a), y = _words(b);
  final u = x.union(y).length;
  return u == 0 ? 0 : x.intersection(y).length / u;
}

/// Bilder-Quiz: Bild zeigen, aus vier Aussagen die passende wählen.
List<ImageQuizItem> imageQuiz(QuestionBank bank, int count, {Random? rng, Chapter? chapter}) {
  final r = rng ?? Random();
  final groups = bank.imageGroups.where((g) => chapter == null || g.chapter == chapter).toList()..shuffle(r);
  final items = <ImageQuizItem>[];
  for (final g in groups) {
    if (items.length >= count) break;
    final image = g.images.first;
    final trues = g.questions.where((q) => q.answer && q.image == image).toList();
    final correct = trues[r.nextInt(trues.length)];
    // Ablenker: richtige Aussagen zu anderen Bildern, möglichst aus demselben Kapitel,
    // die keiner Aussage zu diesem Bild ähneln (sonst wären sie womöglich auch richtig).
    bool usable(Question q) =>
        q.answer && q.image != null && q.image != image && g.questions.every((own) => _similar(own.de, q.de) < 0.34);
    final sameChapter = [for (final o in bank.imageGroups) if (o != g && o.chapter == g.chapter) ...o.questions.where(usable)]..shuffle(r);
    final other = [for (final o in bank.imageGroups) if (o.chapter != g.chapter) ...o.questions.where(usable)]..shuffle(r);
    final distractors = <Question>[];
    final usedGroups = <int>{g.id};
    for (final q in [...sameChapter, ...other]) {
      if (distractors.length >= 3) break;
      if (!usedGroups.add(q.group.id)) continue;
      if (distractors.any((d) => _similar(d.de, q.de) > 0.5)) continue;
      distractors.add(q);
    }
    if (distractors.length < 3) continue;
    final options = [correct, ...distractors]..shuffle(r);
    items.add(ImageQuizItem(g, image, options, correct));
  }
  return items;
}

// ---------- Prüfung teilen ----------

/// Prüfungscodes sind sechsstellig; derselbe Code ergibt bei allen dieselben 30 Fragen.
int newExamCode([Random? rng]) => 100000 + (rng ?? Random()).nextInt(900000);

int? parseExamCode(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 6) return null;
  final v = int.parse(digits);
  return v >= 100000 ? v : null;
}

// ---------- Erfolge und Abzeichen ----------

class Achievement {
  final String id;
  final String emoji;
  final String de;
  final String it;
  final String descDe;
  final String descIt;
  final bool unlocked;
  final double progress; // 0..1

  const Achievement(this.id, this.emoji, this.de, this.it, this.descDe, this.descIt, this.unlocked, this.progress);

  String title(bool italian) => italian ? it : de;
  String description(bool italian) => italian ? descIt : descDe;
}

/// Alle Abzeichen, berechnet aus dem Lernstand (keine eigene Speicherung nötig).
List<Achievement> achievements(Progress p, QuestionBank bank) {
  final total = bank.questions.length;
  final learned = p.learnedCount;
  final seen = p.seenCount;
  final best = p.bestDayStreak;
  final official = p.exams.where((x) => x.official).toList(); // neueste zuerst
  final passed = official.where((x) => p.examErrors(x) <= x.maxErrors).length;
  final perfect = official.any((x) => p.examErrors(x) == 0);
  var inARow = 0, bestRow = 0;
  for (final x in official.reversed) {
    inARow = p.examErrors(x) <= x.maxErrors ? inARow + 1 : 0;
    bestRow = max(bestRow, inARow);
  }
  final greenChapters = p.chapters.where((c) => chapterReadiness(c) == Readiness.green).length;
  final goalDays = p.days.values.where((d) => d.answered >= p.settings.dailyGoal).length;
  final hours = p.totalStudySeconds / 3600;
  final trickyLearned = bank.trickyQuestions.where(p.isLearned).length;
  final pass = p.passProbability();

  Achievement a(String id, String emoji, String de, String it, String descDe, String descIt, num value, num goal) =>
      Achievement(id, emoji, de, it, descDe, descIt, value >= goal, goal == 0 ? 1 : min(1, value / goal).toDouble());

  return [
    a('first', '🚗', 'Losgefahren', 'Si parte', 'Die erste Frage beantwortet', 'Prima domanda risolta', seen, 1),
    a('seen100', '📘', 'Fleißig', 'Diligente', '100 verschiedene Aussagen beantwortet', '100 affermazioni diverse', seen, 100),
    a('seen1000', '📚', 'Bücherwurm', 'Topo di biblioteca', '1.000 verschiedene Aussagen beantwortet', '1.000 affermazioni diverse', seen, 1000),
    a('seenAll', '🗺️', 'Alles gesehen', 'Visto tutto', 'Jede der $total Aussagen mindestens einmal beantwortet',
        'Tutte le $total affermazioni almeno una volta', seen, total),
    a('learned500', '🧠', 'Gut im Kopf', 'Ben memorizzato', '500 Aussagen gelernt', '500 affermazioni imparate', learned, 500),
    a('learnedAll', '🎓', 'Meister', 'Maestro', 'Alle Aussagen gelernt', 'Tutte le affermazioni imparate', learned, total),
    a('streak3', '🔥', 'Dranbleiben', 'Costanza', '3 Tage in Folge gelernt', '3 giorni di fila', best, 3),
    a('streak7', '🔥', 'Eine Woche am Stück', 'Una settimana di fila', '7 Tage in Folge gelernt', '7 giorni di fila', best, 7),
    a('streak30', '🏅', 'Eiserner Wille', 'Volontà di ferro', '30 Tage in Folge gelernt', '30 giorni di fila', best, 30),
    a('goal7', '🎯', 'Zielstrebig', 'Determinato', 'An 7 Tagen das Tagesziel erreicht', 'Obiettivo raggiunto in 7 giorni', goalDays, 7),
    a('hours10', '⏱️', 'Zehn Stunden', 'Dieci ore', '10 Stunden gelernt', '10 ore di studio', hours, 10),
    a('exam1', '📝', 'Erste Prüfung', 'Primo esame', 'Eine Prüfungssimulation bestanden', 'Una simulazione superata', passed, 1),
    a('exam10', '🏆', 'Prüfungsprofi', 'Esperto d\'esame', '10 Prüfungssimulationen bestanden', '10 simulazioni superate', passed, 10),
    a('row5', '⭐', 'Fünf in Folge', 'Cinque di fila', '5 Simulationen hintereinander bestanden', '5 simulazioni di fila superate', bestRow, 5),
    a('perfect', '💯', 'Fehlerfrei', 'Senza errori', 'Eine Simulation ohne einen einzigen Fehler', 'Una simulazione senza errori', perfect ? 1 : 0, 1),
    a('green5', '🟢', 'Fünf Kapitel grün', 'Cinque capitoli verdi', '5 Kapitel auf der Ampel grün', '5 capitoli verdi', greenChapters, 5),
    a('greenAll', '🚦', 'Alles grün', 'Tutto verde', 'Alle Kapitel auf der Ampel grün', 'Tutti i capitoli verdi', greenChapters, p.chapters.length),
    a('tricky', '🪤', 'Fallensucher', 'Cacciatore di trappole', '100 Fallen-Fragen gelernt', '100 domande trabocchetto imparate', trickyLearned, 100),
    a('ready', '✅', 'Prüfungsreif', 'Pronto per l\'esame', 'Bestehenschance über 90 %', 'Probabilità di superare oltre il 90 %', pass, 0.9),
  ];
}

/// Ereignisse dieses Geräts von heute (für Tests und Anzeigen).
int answersToday(UserData data, String deviceId) {
  final key = dayKey(DateTime.now());
  return (data.events[deviceId] ?? const <AnswerEvent>[])
      .where((e) => dayKey(DateTime.fromMillisecondsSinceEpoch(e.ts * 1000)) == key)
      .length;
}
