import 'package:flutter_test/flutter_test.dart';
import 'package:fuehrerschein_quiz/data/progress.dart';
import 'package:fuehrerschein_quiz/data/question_bank.dart';
import 'package:fuehrerschein_quiz/data/session_builder.dart';
import 'package:fuehrerschein_quiz/data/user_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuestionBank bank;
  setUpAll(() async => bank = await QuestionBank.load());

  test('alle Fragen sind geladen und einem Buchkapitel zugeordnet', () {
    expect(bank.questions.length, 7020);
    expect(bank.examChapters.length, 25);
    expect(bank.chapters.length, greaterThanOrEqualTo(20));
    final total = bank.chapters.fold<int>(0, (s, c) => s + c.questions.length);
    expect(total, 7020);
    for (final c in bank.chapters) {
      // ignore: avoid_print
      print('Buchkapitel ${c.id.toString().padLeft(2)}: ${c.questions.length.toString().padLeft(4)} Aussagen  ${c.de}');
    }
  });

  test('Fallen-Fragen: sinnvolle Menge', () {
    final tricky = bank.trickyQuestions.length;
    // ignore: avoid_print
    print('Fallen-Fragen: $tricky');
    expect(tricky, inInclusiveRange(300, 2500));
  });

  test('offizielle Prüfung: 30 Fragen aus allen 25 Ministeriumskapiteln, keine Gruppe doppelt', () {
    final p = Progress(bank, UserData());
    final exam = SessionBuilder(bank, p, {}).officialExam();
    expect(exam.length, 30);
    expect({for (final q in exam) q.examChapter.id}.length, 25);
    expect({for (final q in exam) q.group.id}.length, 30);
  });

  test('schwierige Fragen nach Fehlern', () {
    final q = bank.questions.first;
    final data = UserData(events: {
      'x': [AnswerEvent(q.id, 1, false, 0), AnswerEvent(q.id, 2, false, 0), AnswerEvent(q.id, 3, true, 0)],
    });
    final p = Progress(bank, data);
    expect(p.isHard(q), isTrue);
    final session = SessionBuilder(bank, p, {}).difficultSession(20);
    expect(session.length, 20);
    expect(session.contains(q), isTrue);
  });
}
