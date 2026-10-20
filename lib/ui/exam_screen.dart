import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/question_bank.dart';
import '../data/session_builder.dart';
import '../data/user_data.dart';
import 'quiz_screen.dart';
import 'widgets.dart';

class ExamConfig {
  final List<Question> questions;
  final int limitSec; // 0 = ohne Zeitlimit
  final int maxErrors;
  final bool official;
  final bool immediate;

  ExamConfig({
    required this.questions,
    required this.limitSec,
    required this.maxErrors,
    required this.official,
    required this.immediate,
  });
}

Future<void> startOfficialExam(BuildContext context) {
  final app = context.read<AppState>();
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ExamScreen(
      config: ExamConfig(
        questions: app.builder.officialExam(),
        limitSec: AppConfig.examMinutes * 60,
        maxErrors: AppConfig.examMaxErrors,
        official: true,
        immediate: app.settings.examImmediateFeedback,
      ),
    ),
  ));
}

/// Prüfungssimulation im Stil der Ministeriums-Prüfung.
class ExamScreen extends StatefulWidget {
  final ExamConfig config;
  const ExamScreen({super.key, required this.config});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late final List<int> _answers = List.filled(widget.config.questions.length, -1);
  int _index = 0;
  late final int _start = nowSeconds();
  final _watch = Stopwatch()..start();
  Timer? _timer;
  bool _finished = false;

  List<Question> get _qs => widget.config.questions;

  int get _elapsed => _watch.elapsed.inSeconds;
  int get _remaining => widget.config.limitSec - _elapsed;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().sessionActive = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.config.limitSec > 0 && _remaining <= 0) {
        _submit(timeUp: true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _answer(bool value) {
    if (widget.config.immediate && _answers[_index] != -1) return;
    setState(() => _answers[_index] = value ? 1 : 0);
    if (!widget.config.immediate) {
      // Wie bei der echten Prüfung automatisch zur nächsten unbeantworteten Frage.
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || _finished) return;
        final next = _nextUnanswered();
        if (next != null) setState(() => _index = next);
      });
    }
  }

  int? _nextUnanswered() {
    for (var i = 1; i <= _qs.length; i++) {
      final j = (_index + i) % _qs.length;
      if (_answers[j] == -1) return j;
    }
    return null;
  }

  Future<void> _confirmSubmit() async {
    final app = context.read<AppState>();
    final open = _answers.where((a) => a == -1).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.italianUi ? 'Consegnare la scheda?' : 'Prüfung abgeben?'),
        content: Text(open > 0
            ? (app.italianUi
                ? 'Ci sono ancora $open domande senza risposta (contano come errori).'
                : 'Es sind noch $open Fragen unbeantwortet (zählen als Fehler).')
            : (app.italianUi ? 'Hai risposto a tutte le domande.' : 'Du hast alle Fragen beantwortet.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.italianUi ? 'Indietro' : 'Zurück')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.italianUi ? 'Consegna' : 'Abgeben')),
        ],
      ),
    );
    if (ok == true) _submit();
  }

  void _submit({bool timeUp = false}) {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    final app = context.read<AppState>();
    final duration = widget.config.limitSec > 0 ? min(_elapsed, widget.config.limitSec) : _elapsed;
    final record = ExamRecord(
      id: randomId(),
      start: _start,
      durationSec: duration,
      limitSec: widget.config.limitSec,
      official: widget.config.official,
      maxErrors: widget.config.maxErrors,
      qids: [for (final q in _qs) q.id],
      answers: List.of(_answers),
    );
    app.saveExam(record);
    app.addStudySeconds(duration);
    app.sessionFinished();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ExamResultScreen(record: record, timeUp: timeUp),
    ));
  }

  Future<bool> _confirmExit() async {
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.italianUi ? 'Abbandonare l\'esame?' : 'Prüfung abbrechen?'),
        content: Text(app.italianUi
            ? 'L\'esame non verrà salvato.'
            : 'Die Prüfung wird nicht gewertet und nicht gespeichert.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.italianUi ? 'Continua' : 'Weitermachen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.italianUi ? 'Abbandona' : 'Abbrechen')),
        ],
      ),
    );
    if (ok == true) app.sessionFinished();
    return ok == true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyR || k == LogicalKeyboardKey.keyV || k == LogicalKeyboardKey.digit1) {
      _answer(true);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.digit2) {
      _answer(false);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.enter) {
      setState(() => _index = min(_index + 1, _qs.length - 1));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _index = max(_index - 1, 0));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final q = _qs[_index];
    final answered = _answers.where((a) => a != -1).length;
    final lowTime = widget.config.limitSec > 0 && _remaining <= 120;
    final showSolution = widget.config.immediate && _answers[_index] != -1;
    final wide = isWide(context);

    final grid = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _qs.length; i++)
          _NumberBox(
            number: i + 1,
            current: i == _index,
            answered: _answers[i] != -1,
            result: widget.config.immediate && _answers[i] != -1 ? ((_answers[i] == 1) == _qs[i].answer) : null,
            onTap: () => setState(() => _index = i),
          ),
      ],
    );

    final questionArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(6)),
              child: Text(
                context.tr('Frage ${_index + 1}', 'Domanda ${_index + 1}'),
                style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(q.chapter.name(app.italianUi),
                  style: theme.textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: wide || q.imageAsset == null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (q.imageAsset != null) ...[QuestionImage(asset: q.imageAsset!, size: 220), const SizedBox(width: 20)],
                    Expanded(child: QuestionText(question: q, fontSize: 20)),
                  ],
                )
              : Column(
                  children: [
                    QuestionImage(asset: q.imageAsset!, size: 180),
                    const SizedBox(height: 14),
                    QuestionText(question: q),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        AnswerButtons(
          selected: _answers[_index] == -1 ? null : _answers[_index] == 1,
          correct: showSolution ? q.answer : null,
          onAnswer: _answer,
          italian: app.italianUi,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _index > 0 ? () => setState(() => _index--) : null,
              icon: const Icon(Icons.chevron_left),
              label: Text(context.tr('Zurück', 'Indietro')),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _index < _qs.length - 1 ? () => setState(() => _index++) : null,
              icon: const Icon(Icons.chevron_right),
              label: Text(context.tr('Weiter', 'Avanti')),
            ),
          ],
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) Navigator.of(context).pop();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.config.official
                ? context.tr('Prüfungssimulation', 'Simulazione d\'esame')
                : context.tr('Eigenes Quiz', 'Quiz personalizzato')),
            actions: [
              if (widget.config.limitSec > 0)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lowTime ? wrongColor : theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 18, color: lowTime ? Colors.white : null),
                      const SizedBox(width: 6),
                      Text(
                        formatClock(max(0, _remaining)),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: lowTime ? Colors.white : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _confirmSubmit,
                  child: Text(context.tr('Abgeben', 'Consegna')),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ContentWidth(
                maxWidth: 1000,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('$answered von ${_qs.length} beantwortet', '$answered di ${_qs.length} risposte'),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    grid,
                    const SizedBox(height: 16),
                    questionArea,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberBox extends StatelessWidget {
  final int number;
  final bool current;
  final bool answered;
  final bool? result;
  final VoidCallback onTap;
  const _NumberBox({
    required this.number,
    required this.current,
    required this.answered,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg = cs.surfaceContainerHighest;
    Color fg = cs.onSurface;
    if (result != null) {
      bg = result! ? correctColor : wrongColor;
      fg = Colors.white;
    } else if (answered) {
      bg = cs.primary;
      fg = cs.onPrimary;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: current ? Border.all(color: cs.tertiary, width: 3) : null,
        ),
        child: Text('$number', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Ergebnis einer Prüfung (auch aus der Historie aufrufbar).
class ExamResultScreen extends StatelessWidget {
  final ExamRecord record;
  final bool timeUp;
  const ExamResultScreen({super.key, required this.record, this.timeUp = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final qs = [for (final id in record.qids) app.bank.byId[id]].whereType<Question>().toList();
    final answers = [for (final a in record.answers) a == -1 ? null : a == 1];
    final errors = app.progress.examErrors(record);
    final passed = errors <= record.maxErrors;
    final wrongIdx = [for (var i = 0; i < qs.length; i++) if (answers[i] != qs[i].answer) i];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Prüfungsergebnis', 'Esito dell\'esame'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: passed ? correctColor : wrongColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(passed ? Icons.emoji_events : Icons.sentiment_dissatisfied, color: Colors.white, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        passed ? context.tr('BESTANDEN', 'PROMOSSO') : context.tr('NICHT BESTANDEN', 'RESPINTO'),
                        style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          '$errors ${errors == 1 ? 'Fehler' : 'Fehler'} (erlaubt: ${record.maxErrors})',
                          '$errors ${errors == 1 ? 'errore' : 'errori'} (ammessi: ${record.maxErrors})',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      if (timeUp)
                        Text(context.tr('Die Zeit ist abgelaufen.', 'Il tempo è scaduto.'),
                            style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Wrap(
                    spacing: 32,
                    runSpacing: 12,
                    children: [
                      StatTile(value: '${qs.length - errors}/${qs.length}', label: context.tr('richtig', 'corrette')),
                      StatTile(value: formatClock(record.durationSec), label: context.tr('Zeit', 'Tempo')),
                      StatTile(
                        value: formatDate(DateTime.fromMillisecondsSinceEpoch(record.start * 1000), withTime: true),
                        label: context.tr('Datum', 'Data'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (wrongIdx.isNotEmpty)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => startQuiz(
                            context,
                            context.trNow('Prüfungsfehler üben', 'Ripassa gli errori'),
                            [for (final i in wrongIdx) qs[i]],
                            immediate: true,
                          ),
                          icon: const Icon(Icons.replay),
                          label: Text(context.tr('Fehler üben', 'Ripassa errori')),
                        ),
                      ),
                    if (wrongIdx.isNotEmpty) const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          if (record.official) startOfficialExam(context);
                        },
                        icon: Icon(record.official ? Icons.refresh : Icons.check),
                        label: Text(record.official ? context.tr('Neue Prüfung', 'Nuovo esame') : context.tr('Fertig', 'Fine')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (wrongIdx.isNotEmpty) ...[
                  Text(context.tr('Fehler', 'Errori'), style: theme.textTheme.titleMedium),
                  for (final i in wrongIdx) AnsweredQuestionTile(question: qs[i], userAnswer: answers[i]),
                  const SizedBox(height: 16),
                ],
                Text(context.tr('Richtig beantwortet', 'Risposte corrette'), style: theme.textTheme.titleMedium),
                for (var i = 0; i < qs.length; i++)
                  if (!wrongIdx.contains(i)) AnsweredQuestionTile(question: qs[i], userAnswer: answers[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Einstellungen für ein eigenes Quiz.
class CustomQuizSheet extends StatefulWidget {
  const CustomQuizSheet({super.key});

  @override
  State<CustomQuizSheet> createState() => _CustomQuizSheetState();
}

class _CustomQuizSheetState extends State<CustomQuizSheet> {
  int _count = 30;
  int _minutes = 20;
  int _maxErrors = 3;
  bool _immediate = false;
  QuestionFilter _filter = QuestionFilter.all;
  late Set<int> _chapters = _allChapters;

  Set<int> get _allChapters => {for (final c in context.read<AppState>().bank.chapters) c.id};

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final total = app.bank.chapters.length;
    final filters = {
      QuestionFilter.all: context.tr('Alle Fragen', 'Tutte'),
      QuestionFilter.unseen: context.tr('Noch nie beantwortet', 'Mai risposte'),
      QuestionFilter.notLearned: context.tr('Noch nicht gelernt', 'Non ancora imparate'),
      QuestionFilter.errors: context.tr('Meine Fehler', 'I miei errori'),
      QuestionFilter.hard: context.tr('Meine schwierigen Fragen', 'Le mie domande difficili'),
      QuestionFilter.tricky: context.tr('Fallen-Fragen (ähnlich klingend)', 'Domande trabocchetto'),
      QuestionFilter.favorites: context.tr('Favoriten', 'Preferite'),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Eigenes Quiz', 'Quiz personalizzato'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(context.tr('Anzahl Fragen: $_count', 'Numero di domande: $_count')),
            Slider(value: _count.toDouble(), min: 5, max: 100, divisions: 19, label: '$_count',
                onChanged: (v) => setState(() => _count = v.round())),
            Text(_minutes == 0
                ? context.tr('Zeitlimit: keines', 'Tempo: illimitato')
                : context.tr('Zeitlimit: $_minutes Minuten', 'Tempo: $_minutes minuti')),
            Slider(value: _minutes.toDouble(), min: 0, max: 60, divisions: 12, label: '$_minutes',
                onChanged: (v) => setState(() => _minutes = v.round())),
            Text(context.tr('Erlaubte Fehler: $_maxErrors', 'Errori ammessi: $_maxErrors')),
            Slider(value: _maxErrors.toDouble(), min: 0, max: 10, divisions: 10, label: '$_maxErrors',
                onChanged: (v) => setState(() => _maxErrors = v.round())),
            const SizedBox(height: 8),
            DropdownButtonFormField<QuestionFilter>(
              value: _filter,
              decoration: InputDecoration(labelText: context.tr('Fragen', 'Domande'), border: const OutlineInputBorder()),
              items: [for (final e in filters.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _filter = v ?? QuestionFilter.all),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Lösung sofort zeigen', 'Mostra subito la soluzione')),
              value: _immediate,
              onChanged: (v) => setState(() => _immediate = v),
            ),
            Row(
              children: [
                Expanded(child: Text(context.tr('Kapitel (${_chapters.length}/$total)', 'Capitoli (${_chapters.length}/$total)'),
                    style: theme.textTheme.titleSmall)),
                TextButton(
                  onPressed: () => setState(() => _chapters = _chapters.length == total ? {} : _allChapters),
                  child: Text(_chapters.length == total ? context.tr('Keine', 'Nessuno') : context.tr('Alle', 'Tutti')),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in app.bank.chapters)
                  FilterChip(
                    label: Text('${c.id}. ${c.name(app.italianUi)}', overflow: TextOverflow.ellipsis),
                    selected: _chapters.contains(c.id),
                    onSelected: (s) => setState(() => s ? _chapters.add(c.id) : _chapters.remove(c.id)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _chapters.isEmpty
                  ? null
                  : () {
                      final qs = app.builder.customQuiz(count: _count, chapters: _chapters, filter: _filter);
                      Navigator.pop(context);
                      if (qs.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(context.trNow('Keine passenden Fragen gefunden.', 'Nessuna domanda trovata.')),
                        ));
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ExamScreen(
                          config: ExamConfig(
                            questions: qs,
                            limitSec: _minutes * 60,
                            maxErrors: _maxErrors,
                            official: false,
                            immediate: _immediate,
                          ),
                        ),
                      ));
                    },
              icon: const Icon(Icons.play_arrow),
              label: Text(context.tr('Quiz starten', 'Inizia il quiz')),
            ),
          ],
        ),
      ),
    );
  }
}
