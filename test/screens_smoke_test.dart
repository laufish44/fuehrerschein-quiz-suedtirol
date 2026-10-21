import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuehrerschein_quiz/app_state.dart';
import 'package:fuehrerschein_quiz/data/study_features.dart';
import 'package:fuehrerschein_quiz/data/user_data.dart';
import 'package:fuehrerschein_quiz/services/update_service.dart';
import 'package:fuehrerschein_quiz/ui/exam_tab.dart';
import 'package:fuehrerschein_quiz/ui/home_tab.dart';
import 'package:fuehrerschein_quiz/ui/learn_tab.dart';
import 'package:fuehrerschein_quiz/ui/more_tab.dart';
import 'package:fuehrerschein_quiz/ui/study_features_ui.dart';
import 'package:provider/provider.dart';

/// Rendert die neuen Seiten einmal, damit Layout-Fehler auffallen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('fq_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    app = await AppState.load();
    // Etwas Lernstand und ein Prüfungstermin, damit Lernplan und Abzeichen etwas zeigen.
    app.updateSettings((s) => s.examDate = DateTime.now().add(const Duration(days: 20)).toIso8601String().substring(0, 10));
    for (final q in app.bank.questions.take(150)) {
      app.recordAnswer(q, true);
    }
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider(create: (_) => UpdateService()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Startseite mit Lernplan, Abzeichen und neuen Kacheln', (tester) async {
    await pump(tester, const HomeTab());
    expect(find.textContaining('Lernplan'), findsOneWidget);
    expect(find.textContaining('Neues Abzeichen'), findsNothing); // mehrere neu → „x neue Abzeichen!“
    expect(find.textContaining('neue Abzeichen'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gegensatzpaare'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Bilder-Quiz'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lernen-Tab mit Ampel', (tester) async {
    await pump(tester, const LearnTab());
    expect(find.byType(ReadinessDot), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Prüfung-Tab mit Code teilen', (tester) async {
    await pump(tester, const ExamTab());
    expect(find.text('Code erstellen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mehr-Tab, Ampel, Erfolge', (tester) async {
    await pump(tester, const MoreTab());
    expect(find.text('Erfolge und Abzeichen'), findsOneWidget);
    await pump(tester, const ReadinessScreen());
    expect(find.textContaining('Rote und gelbe'), findsOneWidget);
    await pump(tester, const AchievementsScreen());
    await tester.pump();
    expect(find.text('Losgefahren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Verbesserungsvorschlag-Dialog', (tester) async {
    await pump(tester, const MoreTab());
    await tester.scrollUntilVisible(find.text('Verbesserung vorschlagen'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Verbesserung vorschlagen'));
    await tester.pumpAndSettle();
    final weiter = find.widgetWithText(FilledButton, 'Weiter zu GitHub');
    expect(tester.widget<FilledButton>(weiter).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, 'Dunkles Widget');
    await tester.pump();
    expect(tester.widget<FilledButton>(weiter).onPressed, isNotNull);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Weiter zu GitHub'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gegensatzpaare durchspielen', (tester) async {
    final pair = app.bank.oppositePairs.first;
    await pump(tester, PairsScreen(pairs: [pair]));
    final richtig = find.text('RICHTIG');
    expect(richtig, findsNWidgets(2));
    await tester.tap(richtig.first);
    await tester.tap(find.text('FALSCH').last);
    await tester.pump();
    await tester.tap(find.text('Prüfen'));
    await tester.pump();
    expect(find.text('Weiter'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2)); // verzögertes Speichern abwarten
  });

  testWidgets('Bilder-Quiz zeigt vier Antworten', (tester) async {
    await pump(tester, ImageQuizScreen(items: imageQuiz(app.bank, 2)));
    expect(find.byType(OutlinedButton), findsNWidgets(4));
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();
    expect(find.text('Weiter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Lernstand wurde gezählt', () {
    expect(app.data.events.values.expand((e) => e).where((e) => e.mode == AnswerMode.practice).length, greaterThanOrEqualTo(150));
  });
}
