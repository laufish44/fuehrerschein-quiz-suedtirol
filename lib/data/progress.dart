import 'dart:math';

import 'question_bank.dart';
import 'user_data.dart';

/// Lernstand einer einzelnen Frage, berechnet aus allen Antworten.
class QuestionStat {
  int attempts = 0;
  int correct = 0;
  int wrong = 0;
  int lastTs = 0;
  bool lastCorrect = false;
  int streak = 0; // richtige Antworten in Folge
  double _s = 0; // gewichtete richtige Antworten (neuere zählen mehr)
  double _w = 0;

  void add(AnswerEvent e) {
    attempts++;
    if (e.correct) {
      correct++;
      streak++;
    } else {
      wrong++;
      streak = 0;
    }
    lastTs = e.ts;
    lastCorrect = e.correct;
    _s = _s * 0.6 + (e.correct ? 1 : 0);
    _w = _w * 0.6 + 1;
  }

  /// Geschätzte Wahrscheinlichkeit, diese Frage jetzt richtig zu beantworten.
  double get pCorrect => (1 + _s) / (2 + _w);
}

class DayStat {
  int answered = 0;
  int correct = 0;
  int seconds = 0;
}

class ChapterStat {
  final Chapter chapter;
  int total = 0;
  int seen = 0;
  int learned = 0;
  int errors = 0;
  int attempts = 0;
  int correct = 0;
  double pSum = 0;

  ChapterStat(this.chapter);

  double get accuracy => attempts == 0 ? 0 : correct / attempts;
  double get learnedRatio => total == 0 ? 0 : learned / total;
  double get seenRatio => total == 0 ? 0 : seen / total;
  double get knowledge => total == 0 ? 0 : pSum / total;
}

/// Spaced-Repetition-Abstände je nach Anzahl richtiger Antworten in Folge.
const _reviewIntervals = [0, 20 * 3600, 3 * 86400, 7 * 86400, 14 * 86400, 30 * 86400, 60 * 86400];

/// Alle aus dem Lernstand abgeleiteten Zahlen.
class Progress {
  final QuestionBank bank;
  final SyncedSettings settings;
  final Map<int, QuestionStat> stats = {};
  final Map<String, DayStat> days = {};
  final List<ExamRecord> exams;
  late final List<ChapterStat> chapters;
  int totalAnswers = 0;
  int totalCorrect = 0;

  Progress(this.bank, UserData data)
      : settings = data.settings,
        exams = data.exams.values.toList()..sort((a, b) => b.start.compareTo(a.start)) {
    final all = <AnswerEvent>[for (final l in data.events.values) ...l]..sort((a, b) => a.ts.compareTo(b.ts));
    for (final e in all) {
      if (!bank.byId.containsKey(e.qid)) continue;
      (stats[e.qid] ??= QuestionStat()).add(e);
      final d = days[dayKey(DateTime.fromMillisecondsSinceEpoch(e.ts * 1000))] ??= DayStat();
      d.answered++;
      if (e.correct) d.correct++;
      totalAnswers++;
      if (e.correct) totalCorrect++;
    }
    for (final dev in data.studySeconds.values) {
      for (final entry in dev.entries) {
        (days[entry.key] ??= DayStat()).seconds += entry.value;
      }
    }
    chapters = [for (final c in bank.chapters) _chapterStat(c)];
    _chapterById = {for (final cs in chapters) cs.chapter.id: cs};
  }

  late final Map<int, ChapterStat> _chapterById;

  /// Lernstand eines Buchkapitels.
  ChapterStat chapterStat(Chapter c) => _chapterById[c.id] ?? _chapterStat(c);

  ChapterStat _chapterStat(Chapter c) {
    final cs = ChapterStat(c);
    for (final q in c.questions) {
      cs.total++;
      final s = stats[q.id];
      cs.pSum += s?.pCorrect ?? 0.5;
      if (s == null) continue;
      cs.seen++;
      cs.attempts += s.attempts;
      cs.correct += s.correct;
      if (isLearned(q)) cs.learned++;
      if (isError(q)) cs.errors++;
    }
    return cs;
  }

  QuestionStat? stat(Question q) => stats[q.id];

  bool isNew(Question q) => stats[q.id] == null;
  bool isLearned(Question q) => (stats[q.id]?.streak ?? 0) >= settings.learnedStreak;
  bool isError(Question q) {
    final s = stats[q.id];
    return s != null && s.wrong > 0 && s.streak < settings.errorClearStreak;
  }

  bool isDue(Question q, int now) {
    final s = stats[q.id];
    if (s == null) return false;
    final interval = _reviewIntervals[min(s.streak, _reviewIntervals.length - 1)];
    return now >= s.lastTs + interval;
  }

  /// Persönlich schwierige Fragen: mehrmals oder kürzlich falsch beantwortet und noch nicht sicher.
  bool isHard(Question q) {
    final s = stats[q.id];
    if (s == null || s.wrong == 0) return false;
    return s.pCorrect < 0.7 || (s.wrong >= 2 && s.wrong / s.attempts >= 0.3);
  }

  List<Question> get errorQuestions => [for (final q in bank.questions) if (isError(q)) q];

  /// Persönlich schwierige Fragen, die schwierigsten zuerst.
  List<Question> get hardQuestions {
    final list = [for (final q in bank.questions) if (isHard(q)) q];
    list.sort((a, b) => stats[a.id]!.pCorrect.compareTo(stats[b.id]!.pCorrect));
    return list;
  }

  List<Question> dueQuestions([int? now]) {
    final t = now ?? nowSeconds();
    final due = [for (final q in bank.questions) if (isDue(q, t)) q];
    // Zuerst die, die zuletzt falsch waren, dann die am längsten fälligen.
    due.sort((a, b) {
      final sa = stats[a.id]!, sb = stats[b.id]!;
      if (sa.lastCorrect != sb.lastCorrect) return sa.lastCorrect ? 1 : -1;
      return sa.lastTs.compareTo(sb.lastTs);
    });
    return due;
  }

  int get seenCount => stats.length;
  int get learnedCount => bank.questions.where(isLearned).length;
  double get accuracy => totalAnswers == 0 ? 0 : totalCorrect / totalAnswers;

  /// Die schwersten Fragen: oft falsch beantwortet.
  List<Question> hardestQuestions([int limit = 50]) {
    final list = [
      for (final e in stats.entries)
        if (e.value.wrong > 0) bank.byId[e.key]!,
    ];
    list.sort((a, b) {
      final sa = stats[a.id]!, sb = stats[b.id]!;
      final ra = sa.wrong / sa.attempts, rb = sb.wrong / sb.attempts;
      final c = rb.compareTo(ra);
      return c != 0 ? c : sb.wrong.compareTo(sa.wrong);
    });
    return list.take(limit).toList();
  }

  DayStat today() => days[dayKey(DateTime.now())] ?? DayStat();

  /// Anzahl Tage in Folge (bis heute bzw. gestern) mit mindestens einer Antwort.
  int get dayStreak {
    var d = DateTime.now();
    if ((days[dayKey(d)]?.answered ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    var count = 0;
    while ((days[dayKey(d)]?.answered ?? 0) > 0) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  int get bestDayStreak {
    final keys = days.entries.where((e) => e.value.answered > 0).map((e) => e.key).toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final k in keys) {
      final d = DateTime.parse(k);
      cur = (prev != null && d.difference(prev).inHours.abs() <= 25 && d.day != prev.day) ? cur + 1 : 1;
      best = max(best, cur);
      prev = d;
    }
    return best;
  }

  int get totalStudySeconds => days.values.fold(0, (s, d) => s + d.seconds);

  /// Geschätzte Wahrscheinlichkeit, die offizielle Prüfung (30 Fragen, max. 3 Fehler) zu bestehen.
  double passProbability() {
    final errorProbs = <double>[];
    final weights = examChapterWeights(bank);
    var extraError = 0.0;
    // Die Prüfung wird nach den 25 Ministeriumskapiteln zusammengestellt.
    for (final c in bank.examChapters) {
      final knowledge = c.questions.isEmpty
          ? 0.5
          : c.questions.fold<double>(0, (s, q) => s + (stats[q.id]?.pCorrect ?? 0.5)) / c.questions.length;
      errorProbs.add(1 - knowledge);
      extraError += weights[c.id]! * (1 - knowledge);
    }
    for (var i = 0; i < 30 - bank.examChapters.length; i++) {
      errorProbs.add(extraError);
    }
    // Poisson-Binomial-Verteilung der Fehlerzahl, nur bis maxErrors+1 nötig.
    const maxErrors = 3;
    var dist = List<double>.filled(maxErrors + 2, 0)..[0] = 1;
    for (final p in errorProbs) {
      final next = List<double>.filled(maxErrors + 2, 0);
      for (var k = 0; k <= maxErrors + 1; k++) {
        next[k] += dist[k] * (1 - p);
        final k2 = min(k + 1, maxErrors + 1);
        next[k2] += dist[k] * p;
      }
      dist = next;
    }
    return dist.take(maxErrors + 1).fold(0.0, (s, v) => s + v);
  }

  /// Bestandene Prüfungssimulationen unter den letzten [n] offiziellen.
  ({int passed, int total}) recentOfficialExams(int n) {
    final recent = exams.where((x) => x.official).take(n).toList();
    final passed = recent.where((x) => examErrors(x) <= x.maxErrors).length;
    return (passed: passed, total: recent.length);
  }

  int examErrors(ExamRecord x) {
    var errors = 0;
    for (var i = 0; i < x.qids.length; i++) {
      final q = bank.byId[x.qids[i]];
      if (q == null) continue;
      final a = x.answers[i];
      if (a == -1 || (a == 1) != q.answer) errors++;
    }
    return errors;
  }
}

/// Gewichte der Kapitel für die 5 Zusatzfragen der Prüfung (proportional zur Anzahl Fragengruppen).
Map<int, double> examChapterWeights(QuestionBank bank) {
  final total = bank.groups.length;
  return {for (final c in bank.examChapters) c.id: c.groups.length / total};
}
