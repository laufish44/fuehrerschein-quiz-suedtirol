import 'dart:math';

import 'progress.dart';
import 'question_bank.dart';
import 'user_data.dart';

enum QuestionFilter { all, unseen, notLearned, errors, favorites }

final _rng = Random();

/// Stellt Fragen für Übungsrunden und Prüfungen zusammen.
class SessionBuilder {
  final QuestionBank bank;
  final Progress progress;
  final Set<int> favorites;

  SessionBuilder(this.bank, this.progress, this.favorites);

  bool matches(Question q, QuestionFilter f) => switch (f) {
        QuestionFilter.all => true,
        QuestionFilter.unseen => progress.isNew(q),
        QuestionFilter.notLearned => !progress.isLearned(q),
        QuestionFilter.errors => progress.isError(q),
        QuestionFilter.favorites => favorites.contains(q.id),
      };

  List<Question> chapterQuestions(Chapter c, QuestionFilter f, {bool shuffle = false}) {
    final list = [for (final q in c.questions) if (matches(q, f)) q];
    if (shuffle) list.shuffle(_rng);
    return list;
  }

  /// Offizielle Prüfung: eine Frage aus jedem der 25 Kapitel und 5 weitere aus
  /// zufälligen Kapiteln (gewichtet nach Umfang), nie zwei Fragen aus derselben Gruppe.
  List<Question> officialExam() {
    final weights = examChapterWeights(bank);
    final slots = [for (final c in bank.chapters) c.id];
    final extra = <int>{};
    while (extra.length < 30 - bank.chapters.length) {
      var r = _rng.nextDouble();
      for (final e in weights.entries) {
        r -= e.value;
        if (r <= 0) {
          extra.add(e.key);
          break;
        }
      }
    }
    slots.addAll(extra);
    slots.sort();
    final usedGroups = <int>{};
    final result = <Question>[];
    for (final chapterId in slots) {
      final groups = bank.chapter(chapterId).groups.where((g) => !usedGroups.contains(g.id)).toList();
      final g = groups[_rng.nextInt(groups.length)];
      usedGroups.add(g.id);
      result.add(g.questions[_rng.nextInt(g.questions.length)]);
    }
    return result;
  }

  /// Eigene Prüfung/Quiz: [count] Fragen aus den gewählten Kapiteln.
  List<Question> customQuiz({required int count, required Set<int> chapters, QuestionFilter filter = QuestionFilter.all}) {
    final pool = [
      for (final q in bank.questions)
        if (chapters.contains(q.chapter.id) && matches(q, filter)) q,
    ]..shuffle(_rng);
    // Möglichst nur eine Frage pro Gruppe, damit sich nichts wiederholt.
    final usedGroups = <int>{};
    final result = <Question>[];
    for (final q in pool) {
      if (result.length >= count) break;
      if (usedGroups.add(q.group.id)) result.add(q);
    }
    for (final q in pool) {
      if (result.length >= count) break;
      if (!result.contains(q)) result.add(q);
    }
    result.sort((a, b) => a.chapter.id.compareTo(b.chapter.id));
    return result;
  }

  /// "Intelligent lernen": fällige Wiederholungen zuerst, dann neue Fragen aus den schwächsten Kapiteln.
  List<Question> smartSession(int size) {
    final now = nowSeconds();
    final due = progress.dueQuestions(now);
    final result = <Question>[...due.take((size * 0.6).ceil())];
    final weakChapters = [...progress.chapters]..sort((a, b) => a.knowledge.compareTo(b.knowledge));
    final usedGroups = {for (final q in result) q.group.id};
    for (final cs in weakChapters) {
      if (result.length >= size) break;
      final fresh = cs.chapter.questions.where((q) => progress.isNew(q) && !usedGroups.contains(q.group.id)).toList()
        ..shuffle(_rng);
      for (final q in fresh.take(max(2, size ~/ 4))) {
        if (result.length >= size) break;
        result.add(q);
        usedGroups.add(q.group.id);
      }
    }
    // Falls alles schon gesehen wurde: die unsichersten Fragen.
    if (result.length < size) {
      final rest = [for (final q in bank.questions) if (!result.contains(q)) q]
        ..sort((a, b) => (progress.stat(a)?.pCorrect ?? 0.5).compareTo(progress.stat(b)?.pCorrect ?? 0.5));
      result.addAll(rest.take(size - result.length));
    }
    result.shuffle(_rng);
    return result;
  }
}
