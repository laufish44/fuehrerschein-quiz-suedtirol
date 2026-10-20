import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/question_bank.dart';
import '../services/tts_service.dart';
import 'explanation.dart';
import 'widgets.dart';

/// Startet eine Übungsrunde.
Future<void> startQuiz(BuildContext context, String title, List<Question> questions, {bool? immediate}) async {
  if (questions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.trNow('Keine passenden Fragen gefunden.', 'Nessuna domanda trovata.')),
    ));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => QuizScreen(title: title, questions: questions, immediate: immediate),
  ));
}

/// Übungsmodus: eine Frage nach der anderen, wahlweise mit sofortiger Auflösung.
class QuizScreen extends StatefulWidget {
  final String title;
  final List<Question> questions;
  final bool? immediate;
  const QuizScreen({super.key, required this.title, required this.questions, this.immediate});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _index = 0;
  final Map<int, bool> _answers = {};
  bool _revealed = false;
  late bool _immediate;
  final _watch = Stopwatch();
  final _focus = FocusNode();

  Question get _q => widget.questions[_index];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _immediate = widget.immediate ?? app.settings.practiceImmediateFeedback;
    app.sessionActive = true;
    _watch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRead());
  }

  @override
  void dispose() {
    _focus.dispose();
    TtsService.stop();
    super.dispose();
  }

  void _autoRead() {
    final app = context.read<AppState>();
    if (app.local.ttsAutoRead && mounted) {
      TtsService.speak(_q.text(app.italianQuestions), italian: app.italianQuestions, rate: app.local.ttsRate);
    }
  }

  void _trackTime() {
    final app = context.read<AppState>();
    app.addStudySeconds(min(_watch.elapsed.inSeconds, 120));
    _watch
      ..reset()
      ..start();
  }

  void _answer(bool value) {
    if (_answers.containsKey(_index)) {
      if (_revealed || !_immediate) _next();
      return;
    }
    final app = context.read<AppState>();
    _trackTime();
    _answers[_index] = value;
    app.recordAnswer(_q, value == _q.answer);
    if (_immediate) {
      setState(() => _revealed = true);
      value == _q.answer ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    } else {
      _next();
    }
  }

  void _next() {
    TtsService.stop();
    if (_index >= widget.questions.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
    });
    _autoRead();
  }

  void _previous() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _revealed = _answers.containsKey(_index) && _immediate;
    });
  }

  void _finish() {
    final app = context.read<AppState>();
    app.sessionFinished();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SessionResultScreen(
        title: widget.title,
        questions: widget.questions.take(max(_answers.length, 1)).toList(),
        answers: [for (var i = 0; i < min(_answers.length, widget.questions.length); i++) _answers[i]],
      ),
    ));
  }

  Future<bool> _confirmExit() async {
    if (_answers.isEmpty || _answers.length == widget.questions.length) return true;
    final app = context.read<AppState>();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.italianUi ? 'Interrompere?' : 'Übung beenden?'),
        content: Text(app.italianUi
            ? 'Le risposte date finora sono già salvate.'
            : 'Deine bisherigen Antworten sind schon gespeichert.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: Text(app.italianUi ? 'Continua' : 'Weitermachen')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'result'), child: Text(app.italianUi ? 'Risultato' : 'Auswertung')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'exit'), child: Text(app.italianUi ? 'Esci' : 'Beenden')),
        ],
      ),
    );
    if (r == 'result') {
      _finish();
      return false;
    }
    if (r == 'exit') app.sessionFinished();
    return r == 'exit';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyR || k == LogicalKeyboardKey.keyV || k == LogicalKeyboardKey.digit1) {
      _answer(true);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.digit2) {
      _answer(false);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.arrowRight) {
      if (_answers.containsKey(_index)) _next();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _previous();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final answered = _answers.containsKey(_index);
    final correctSoFar = _answers.entries.where((e) => widget.questions[e.key].answer == e.value).length;
    final wide = isWide(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionToolbar(question: _q),
        if (wide && _q.imageAsset != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuestionImage(asset: _q.imageAsset!, size: 240),
              const SizedBox(width: 20),
              Expanded(child: QuestionText(question: _q, fontSize: 21)),
            ],
          )
        else ...[
          if (_q.imageAsset != null) Center(child: QuestionImage(asset: _q.imageAsset!, size: 190)),
          if (_q.imageAsset != null) const SizedBox(height: 16),
          QuestionText(question: _q),
        ],
        const SizedBox(height: 16),
        if (_revealed) ExplanationPanel(question: _q, userAnswer: _answers[_index]),
        if (!_immediate && answered)
          Text(context.tr('Beantwortet – Auflösung am Ende.', 'Risposta data – soluzione alla fine.'),
              style: theme.textTheme.bodySmall),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) Navigator.of(context).pop();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: _immediate
                    ? context.tr('Auflösung: sofort', 'Soluzione: subito')
                    : context.tr('Auflösung: am Ende', 'Soluzione: alla fine'),
                icon: Icon(_immediate ? Icons.flash_on : Icons.flag_outlined),
                onPressed: () => setState(() => _immediate = !_immediate),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text('${_index + 1} / ${widget.questions.length}', style: theme.textTheme.labelLarge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: (_index + (answered ? 1 : 0)) / widget.questions.length, minHeight: 6),
                      ),
                    ),
                    if (_immediate) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.check, size: 16, color: correctColor),
                      Text('$correctSoFar', style: theme.textTheme.labelLarge),
                      const SizedBox(width: 6),
                      const Icon(Icons.close, size: 16, color: wrongColor),
                      Text('${_answers.length - correctSoFar}', style: theme.textTheme.labelLarge),
                    ],
                  ],
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ContentWidth(child: content),
                  ),
                ),
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: _revealed
                        ? Row(
                            children: [
                              if (_index > 0)
                                IconButton.outlined(onPressed: _previous, icon: const Icon(Icons.arrow_back)),
                              if (_index > 0) const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                                  onPressed: _next,
                                  icon: Icon(_index >= widget.questions.length - 1 ? Icons.flag : Icons.arrow_forward),
                                  label: Text(_index >= widget.questions.length - 1
                                      ? context.tr('Auswertung', 'Risultato')
                                      : context.tr('Weiter', 'Avanti')),
                                ),
                              ),
                            ],
                          )
                        : AnswerButtons(
                            selected: _answers[_index],
                            correct: _revealed ? _q.answer : null,
                            onAnswer: _answer,
                            italian: app.italianUi,
                          ),
                  ),
                ),
                if (app.local.keyboardHints && isWide(context))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      context.tr('Tastatur: R = richtig · F = falsch · Enter = weiter · ← zurück',
                          'Tastiera: V = vero · F = falso · Invio = avanti · ← indietro'),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die beiden großen Antwort-Knöpfe.
class AnswerButtons extends StatelessWidget {
  final bool? selected;
  final bool? correct; // gesetzt = Lösung anzeigen
  final void Function(bool) onAnswer;
  final bool italian;
  final double height;
  const AnswerButtons({
    super.key,
    required this.selected,
    required this.correct,
    required this.onAnswer,
    required this.italian,
    this.height = 64,
  });

  @override
  Widget build(BuildContext context) {
    Widget button(bool value) {
      final label = value ? (italian ? 'VERO' : 'RICHTIG') : (italian ? 'FALSO' : 'FALSCH');
      final isSelected = selected == value;
      Color? bg;
      Color? fg;
      if (correct != null) {
        if (value == correct) {
          bg = correctColor;
          fg = Colors.white;
        } else if (isSelected) {
          bg = wrongColor;
          fg = Colors.white;
        }
      } else if (isSelected) {
        bg = Theme.of(context).colorScheme.primary;
        fg = Theme.of(context).colorScheme.onPrimary;
      }
      return Expanded(
        child: SizedBox(
          height: height,
          child: bg != null
              ? FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
                  onPressed: () => onAnswer(value),
                  child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: value ? correctColor : wrongColor, width: 2),
                    foregroundColor: value ? correctColor : wrongColor,
                  ),
                  onPressed: () => onAnswer(value),
                  child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
        ),
      );
    }

    return Row(children: [button(true), const SizedBox(width: 12), button(false)]);
  }
}

/// Auswertung einer Übungsrunde.
class SessionResultScreen extends StatelessWidget {
  final String title;
  final List<Question> questions;
  final List<bool?> answers;
  const SessionResultScreen({super.key, required this.title, required this.questions, required this.answers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = answers.length;
    final correct = [for (var i = 0; i < n; i++) if (answers[i] == questions[i].answer) i].length;
    final wrongQs = [for (var i = 0; i < n; i++) if (answers[i] != questions[i].answer) questions[i]];
    final ratio = n == 0 ? 0.0 : correct / n;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Auswertung', 'Risultato'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  child: Row(
                    children: [
                      ProgressRing(
                        value: ratio,
                        size: 100,
                        color: scoreColor(ratio),
                        center: Text('${(ratio * 100).round()}%', style: theme.textTheme.titleLarge),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(context.tr('$correct von $n richtig', '$correct su $n corrette'),
                                style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Text(
                              ratio >= 0.9
                                  ? context.tr('Super, weiter so! 🎉', 'Ottimo, continua così! 🎉')
                                  : ratio >= 0.7
                                      ? context.tr('Gut – die Fehler nochmal üben.', 'Bene – ripassa gli errori.')
                                      : context.tr('Dranbleiben, das wird! 💪', 'Non mollare! 💪'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (wrongQs.isNotEmpty)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => QuizScreen(
                              title: context.trNow('Fehler wiederholen', 'Ripassa gli errori'),
                              questions: wrongQs,
                              immediate: true,
                            ),
                          )),
                          icon: const Icon(Icons.replay),
                          label: Text(context.tr('${wrongQs.length} Fehler üben', 'Ripassa ${wrongQs.length} errori')),
                        ),
                      ),
                    if (wrongQs.isNotEmpty) const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.tr('Fertig', 'Fine')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(context.tr('Alle Fragen', 'Tutte le domande'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < n; i++) AnsweredQuestionTile(question: questions[i], userAnswer: answers[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aufklappbare Zeile: Frage, eigene Antwort, Lösung und Erklärung.
class AnsweredQuestionTile extends StatelessWidget {
  final Question question;
  final bool? userAnswer;
  const AnsweredQuestionTile({super.key, required this.question, required this.userAnswer});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ok = userAnswer == question.answer;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          userAnswer == null ? Icons.remove_circle_outline : (ok ? Icons.check_circle : Icons.cancel),
          color: userAnswer == null ? theme.colorScheme.outline : (ok ? correctColor : wrongColor),
        ),
        title: Text(question.text(app.italianQuestions), maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${context.tr('Lösung', 'Soluzione')}: ${question.answer ? context.tr('richtig', 'vero') : context.tr('falsch', 'falso')}'
          '${userAnswer == null ? ' · ${context.tr('nicht beantwortet', 'non risposta')}' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          QuestionToolbar(question: question),
          if (question.imageAsset != null) Center(child: QuestionImage(asset: question.imageAsset!, size: 150)),
          const SizedBox(height: 8),
          QuestionText(question: question, fontSize: 16),
          const SizedBox(height: 12),
          ExplanationPanel(question: question, userAnswer: userAnswer),
        ],
      ),
    );
  }
}
