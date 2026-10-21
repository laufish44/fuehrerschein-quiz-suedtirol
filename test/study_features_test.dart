import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuehrerschein_quiz/data/progress.dart';
import 'package:fuehrerschein_quiz/data/question_bank.dart';
import 'package:fuehrerschein_quiz/data/session_builder.dart';
import 'package:fuehrerschein_quiz/data/study_features.dart';
import 'package:fuehrerschein_quiz/data/user_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuestionBank bank;
  setUpAll(() async => bank = await QuestionBank.load());

  test('Gegensatzpaare: gleiche Gruppe, gegenteilige Lösung, keine Doppelten', () {
    final pairs = bank.oppositePairs;
    // ignore: avoid_print
    print('Gegensatzpaare: ${pairs.length}');
    expect(pairs.length, greaterThan(200));
    final keys = <String>{};
    for (final (a, b) in pairs) {
      expect(a.group, b.group);
      expect(a.answer, isTrue);
      expect(b.answer, isFalse);
      expect(keys.add('${min(a.id, b.id)}-${max(a.id, b.id)}'), isTrue);
    }
  });

  test('Bilder-Quiz: vier Antworten, genau eine zum Bild', () {
    final items = imageQuiz(bank, 40, rng: Random(1));
    expect(items.length, 40);
    for (final it in items) {
      expect(it.options.length, 4);
      expect(it.options.toSet().length, 4);
      expect(it.options.where((o) => o.group == it.group).length, 1);
      expect(it.correct.answer, isTrue);
      expect(it.correct.image, it.image);
      for (final o in it.options) {
        expect(o.answer, isTrue);
      }
    }
  });

  test('Prüfung teilen: gleicher Code = gleiche Fragen, anderer Code = andere', () {
    final b = SessionBuilder(bank, Progress(bank, UserData()), {});
    final a1 = b.officialExam(code: 482193).map((q) => q.id).toList();
    final a2 = b.officialExam(code: 482193).map((q) => q.id).toList();
    final other = b.officialExam(code: 482194).map((q) => q.id).toList();
    expect(a1, a2);
    expect(a1.length, 30);
    expect(a1, isNot(other));
    expect(parseExamCode(' 482 193 '), 482193);
    expect(parseExamCode('12345'), isNull);
  });

  test('Lernplan: verteilt die offenen Aussagen auf die Tage bis zur Prüfung', () {
    final data = UserData()..settings.examDate = '2026-12-01';
    final plan = studyPlan(Progress(bank, data), bank, now: DateTime(2026, 11, 1))!;
    expect(plan.daysLeft, 31);
    expect(plan.remaining, 7020);
    // 7.020 × 2,5 Antworten auf 29 Lerntage ≈ 606 → aufgerundet
    expect(plan.perDay, inInclusiveRange(600, 620));
    final past = studyPlan(Progress(bank, data), bank, now: DateTime(2026, 12, 5))!;
    expect(past.examPassed, isTrue);
    expect(studyPlan(Progress(bank, UserData()), bank), isNull);
  });

  test('Abzeichen: ohne Lernstand keines, nach einer Antwort „Losgefahren“', () {
    final data = UserData();
    expect(achievements(Progress(bank, data), bank).where((a) => a.unlocked), isEmpty);
    data.events['dev'] = [AnswerEvent(bank.questions.first.id, nowSeconds(), true, AnswerMode.practice)];
    final unlocked = achievements(Progress(bank, data), bank).where((a) => a.unlocked).map((a) => a.id);
    expect(unlocked, ['first']);
  });

  test('Ampel: neues Kapitel ist rot', () {
    final p = Progress(bank, UserData());
    expect(p.chapters.every((c) => chapterReadiness(c) == Readiness.red), isTrue);
  });
}
