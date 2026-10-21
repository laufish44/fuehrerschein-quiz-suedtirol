import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/progress.dart';
import '../data/question_bank.dart';
import '../data/study_features.dart';
import 'exam_screen.dart';
import 'quiz_screen.dart';
import 'widgets.dart';

// ---------- Lernplan ----------

class StudyPlanCard extends StatelessWidget {
  const StudyPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final plan = studyPlan(app.progress, app.bank);
    if (plan == null) {
      return SectionCard(
        title: context.tr('Lernplan', 'Piano di studio'),
        trailing: const Icon(Icons.event_outlined),
        onTap: () => pickExamDate(context),
        child: Text(context.tr(
          'Trag deinen Prüfungstermin ein – dann rechnet die App aus, wie viele Fragen du pro Tag schaffen solltest.',
          'Inserisci la data dell\'esame: l\'app calcola quante domande fare ogni giorno.',
        )),
      );
    }
    if (plan.examPassed) {
      return SectionCard(
        title: context.tr('Lernplan', 'Piano di studio'),
        onTap: () => pickExamDate(context),
        child: Text(context.tr('Der Prüfungstermin ist vorbei. Tippen, um einen neuen einzutragen.',
            'La data dell\'esame è passata. Tocca per inserirne una nuova.')),
      );
    }
    final goal = app.settings.dailyGoal;
    final done = plan.doneToday >= plan.perDay;
    return SectionCard(
      title: context.tr('Lernplan · noch ${plan.daysLeft} ${plan.daysLeft == 1 ? 'Tag' : 'Tage'}',
          'Piano di studio · ancora ${plan.daysLeft} ${plan.daysLeft == 1 ? 'giorno' : 'giorni'}'),
      trailing: IconButton(
        tooltip: context.tr('Prüfungstermin ändern', 'Cambia data esame'),
        icon: const Icon(Icons.edit_calendar_outlined),
        onPressed: () => pickExamDate(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            done
                ? context.tr('Heutiges Pensum geschafft! 🎉', 'Obiettivo di oggi raggiunto! 🎉')
                : context.tr('Heute: ${plan.doneToday} von ${plan.perDay} Fragen', 'Oggi: ${plan.doneToday} di ${plan.perDay} domande'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: plan.todayRatio, minHeight: 8, color: done ? correctColor : null),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Noch ${plan.remaining} Aussagen bis „alles gelernt“. Der Plan lässt dir die letzten Tage für Prüfungssimulationen frei.',
              'Ancora ${plan.remaining} affermazioni da imparare. Il piano lascia liberi gli ultimi giorni per le simulazioni.',
            ),
            style: theme.textTheme.bodySmall,
          ),
          if (plan.tight)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.tr('⚠️ Das ist sehr viel pro Tag – plane lieber einen späteren Termin oder lerne mit „Schwierige Fragen“ gezielt.',
                    '⚠️ È molto al giorno – valuta una data più avanti o studia le „Domande difficili“.'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (goal != plan.perDay)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => app.updateSettings((s) => s.dailyGoal = plan.perDay),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(context.tr('Als Tagesziel übernehmen (${plan.perDay})', 'Usa come obiettivo (${plan.perDay})')),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> pickExamDate(BuildContext context) async {
  final app = context.read<AppState>();
  final now = DateTime.now();
  final current = DateTime.tryParse(app.settings.examDate ?? '');
  final picked = await showDatePicker(
    context: context,
    initialDate: current != null && current.isAfter(now) ? current : now.add(const Duration(days: 30)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 730)),
  );
  if (picked != null) {
    app.updateSettings((s) => s.examDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  }
}

// ---------- Prüfungsreif-Ampel ----------

Color readinessColor(Readiness r) => switch (r) {
      Readiness.green => correctColor,
      Readiness.yellow => const Color(0xFFF9A825),
      Readiness.red => wrongColor,
    };

class ReadinessDot extends StatelessWidget {
  final ChapterStat stat;
  final double size;
  const ReadinessDot({super.key, required this.stat, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final r = chapterReadiness(stat);
    return Tooltip(
      message: switch (r) {
        Readiness.green => context.tr('Prüfungsreif', 'Pronto'),
        Readiness.yellow => context.tr('Fast sicher', 'Quasi pronto'),
        Readiness.red => context.tr('Noch Lücken', 'Ancora lacune'),
      },
      child: Container(width: size, height: size, decoration: BoxDecoration(color: readinessColor(r), shape: BoxShape.circle)),
    );
  }
}

/// Übersicht aller Kapitel mit Ampel und gezieltem Üben der roten und gelben.
class ReadinessScreen extends StatelessWidget {
  const ReadinessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final theme = Theme.of(context);
    final byLevel = {for (final r in Readiness.values) r: p.chapters.where((c) => chapterReadiness(c) == r).toList()};
    final weak = [...byLevel[Readiness.red]!, ...byLevel[Readiness.yellow]!];

    void practiceWeak() {
      final pool = <Question>[
        for (final cs in weak)
          ...cs.chapter.questions.where((q) => !p.isLearned(q)),
      ]..shuffle(Random());
      // Fehler zuerst.
      pool.sort((a, b) => (p.isError(b) ? 1 : 0).compareTo(p.isError(a) ? 1 : 0));
      startQuiz(context, context.trNow('Schwache Kapitel', 'Capitoli deboli'), pool.take(app.settings.sessionSize).toList());
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Prüfungsreif-Ampel', 'Semaforo di preparazione'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final r in Readiness.values.reversed)
                        Column(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: readinessColor(r), shape: BoxShape.circle),
                              child: Text('${byLevel[r]!.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 4),
                            Text(switch (r) {
                              Readiness.green => context.tr('sicher', 'sicuri'),
                              Readiness.yellow => context.tr('fast', 'quasi'),
                              Readiness.red => context.tr('Lücken', 'lacune'),
                            }),
                          ],
                        ),
                    ],
                  ),
                ),
                Text(
                  context.tr(
                    'Grün: mindestens 80 % des Kapitels beantwortet, Wissen ≥ 85 % und kaum offene Fehler. Gelb: mindestens die Hälfte beantwortet, Wissen ≥ 70 %.',
                    'Verde: almeno l\'80 % del capitolo risposto, conoscenza ≥ 85 % e quasi nessun errore aperto. Giallo: almeno metà risposta, conoscenza ≥ 70 %.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (weak.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: practiceWeak,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(context.tr('Rote und gelbe Kapitel üben', 'Esercita i capitoli rossi e gialli')),
                  ),
                const SizedBox(height: 12),
                for (final cs in [...p.chapters]..sort((a, b) => a.knowledge.compareTo(b.knowledge)))
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      leading: ReadinessDot(stat: cs, size: 18),
                      title: Text('${cs.chapter.id}. ${cs.chapter.name(app.italianUi)}'),
                      subtitle: Text(context.tr(
                        'Wissen ${(cs.knowledge * 100).round()} % · ${(cs.seenRatio * 100).round()} % beantwortet · ${cs.errors} Fehler',
                        'Conoscenza ${(cs.knowledge * 100).round()} % · ${(cs.seenRatio * 100).round()} % risposte · ${cs.errors} errori',
                      )),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () {
                        final qs = cs.chapter.questions.where((q) => !p.isLearned(q)).toList()..shuffle(Random());
                        startQuiz(context, cs.chapter.name(app.italianUi), qs.take(app.settings.sessionSize).toList());
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Gegensatzpaare ----------

/// Zwei fast gleich klingende Aussagen mit gegenteiliger Lösung nebeneinander beantworten.
class PairsScreen extends StatefulWidget {
  final List<(Question, Question)> pairs;
  const PairsScreen({super.key, required this.pairs});

  static Future<void> open(BuildContext context, {int count = 10}) {
    final app = context.read<AppState>();
    final p = app.progress;
    final all = [...app.bank.oppositePairs]..shuffle(Random());
    // Zuerst Paare, die noch nicht beide gelernt sind.
    all.sort((a, b) {
      int openCount((Question, Question) x) => (p.isLearned(x.$1) ? 0 : 1) + (p.isLearned(x.$2) ? 0 : 1);
      return openCount(b).compareTo(openCount(a));
    });
    final pairs = [for (final pr in all.take(count)) Random().nextBool() ? pr : (pr.$2, pr.$1)];
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PairsScreen(pairs: pairs)));
  }

  @override
  State<PairsScreen> createState() => _PairsScreenState();
}

class _PairsScreenState extends State<PairsScreen> {
  int _index = 0;
  bool? _a;
  bool? _b;
  bool _revealed = false;
  int _bothRight = 0;
  final _watch = Stopwatch()..start();
  late final AppState _app = context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _app.sessionActive = true;
  }

  @override
  void dispose() {
    _app.addStudySeconds(_watch.elapsed.inSeconds);
    _app.sessionFinished();
    super.dispose();
  }

  void _check() {
    final app = context.read<AppState>();
    final (qa, qb) = widget.pairs[_index];
    app.recordAnswer(qa, _a == qa.answer);
    app.recordAnswer(qb, _b == qb.answer);
    if (_a == qa.answer && _b == qb.answer) _bothRight++;
    setState(() => _revealed = true);
  }

  void _next() {
    if (_index >= widget.pairs.length - 1) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.trNow('Fertig!', 'Finito!')),
          content: Text(context.trNow(
            '$_bothRight von ${widget.pairs.length} Paaren komplett richtig.',
            '$_bothRight coppie su ${widget.pairs.length} completamente giuste.',
          )),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    setState(() {
      _index++;
      _a = null;
      _b = null;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    if (widget.pairs.isEmpty) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.compare_arrows, text: context.tr('Keine Paare gefunden.', 'Nessuna coppia trovata.')));
    }
    final (qa, qb) = widget.pairs[_index];
    final image = qa.imageAsset ?? qb.imageAsset;

    Widget side(Question q, bool? value, void Function(bool) set) => Card(
          color: !_revealed ? null : (value == q.answer ? correctBg(context) : wrongBg(context)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(q.text(app.italianQuestions), style: theme.textTheme.titleMedium?.copyWith(height: 1.35)),
                const SizedBox(height: 10),
                AnswerButtons(
                  selected: value,
                  correct: _revealed ? q.answer : null,
                  italian: app.italianUi,
                  height: 44,
                  onAnswer: (v) {
                    if (!_revealed) setState(() => set(v));
                  },
                ),
              ],
            ),
          ),
        );

    final exp = _revealed ? app.bank.explanation(qa, app.italianUi) : null;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Gegensatzpaare ${_index + 1}/${widget.pairs.length}', 'Coppie opposte ${_index + 1}/${widget.pairs.length}'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('Die beiden Aussagen klingen fast gleich – genau eine ist richtig. Beantworte beide.',
                      'Le due affermazioni sembrano quasi uguali – solo una è vera. Rispondi a entrambe.'),
                  style: theme.textTheme.bodyMedium,
                ),
                if (image != null) ...[const SizedBox(height: 12), Center(child: QuestionImage(asset: image, size: 150))],
                const SizedBox(height: 8),
                side(qa, _a, (v) => _a = v),
                side(qb, _b, (v) => _b = v),
                if (_revealed && exp?.group != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('💡 ${exp!.group}', style: theme.textTheme.bodyMedium),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _revealed ? _next : (_a != null && _b != null ? _check : null),
                  child: Text(_revealed ? context.tr('Weiter', 'Avanti') : context.tr('Prüfen', 'Verifica')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Bilder-Quiz ----------

class ImageQuizScreen extends StatefulWidget {
  final List<ImageQuizItem> items;
  const ImageQuizScreen({super.key, required this.items});

  static Future<void> open(BuildContext context, {int count = 15}) {
    final bank = context.read<AppState>().bank;
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageQuizScreen(items: imageQuiz(bank, count))));
  }

  @override
  State<ImageQuizScreen> createState() => _ImageQuizScreenState();
}

class _ImageQuizScreenState extends State<ImageQuizScreen> {
  int _index = 0;
  Question? _chosen;
  int _right = 0;
  final _watch = Stopwatch()..start();
  late final AppState _app = context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _app.sessionActive = true;
  }

  @override
  void dispose() {
    _app.addStudySeconds(_watch.elapsed.inSeconds);
    _app.sessionFinished();
    super.dispose();
  }

  void _choose(Question q) {
    if (_chosen != null) return;
    final item = widget.items[_index];
    if (q == item.correct) {
      _right++;
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    setState(() => _chosen = q);
  }

  void _next() {
    if (_index >= widget.items.length - 1) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.trNow('Bilder-Quiz beendet', 'Quiz figure finito')),
          content: Text(context.trNow('$_right von ${widget.items.length} richtig erkannt.', '$_right su ${widget.items.length} riconosciute.')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    setState(() {
      _index++;
      _chosen = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    if (widget.items.isEmpty) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.image_outlined, text: context.tr('Keine Bilder gefunden.', 'Nessuna figura.')));
    }
    final item = widget.items[_index];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Bilder-Quiz ${_index + 1}/${widget.items.length}', 'Quiz figure ${_index + 1}/${widget.items.length}'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: QuestionImage(asset: 'assets/img/${item.image}.webp', size: 190)),
                const SizedBox(height: 12),
                Text(context.tr('Welche Aussage passt zu diesem Bild?', 'Quale affermazione corrisponde a questa figura?'),
                    style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                for (final o in item.options)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14),
                        backgroundColor: _chosen == null
                            ? null
                            : o == item.correct
                                ? correctBg(context)
                                : o == _chosen
                                    ? wrongBg(context)
                                    : null,
                        side: BorderSide(
                          color: _chosen != null && o == item.correct ? correctColor : theme.colorScheme.outlineVariant,
                          width: _chosen != null && o == item.correct ? 2 : 1,
                        ),
                      ),
                      onPressed: () => _choose(o),
                      child: Text(o.text(app.italianQuestions), style: theme.textTheme.bodyLarge),
                    ),
                  ),
                if (_chosen != null) ...[
                  if (app.bank.explanation(item.correct, app.italianUi).group case final g?)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text('💡 $g', style: theme.textTheme.bodyMedium)),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: _next,
                    child: Text(context.tr('Weiter', 'Avanti')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Prüfung teilen ----------

/// Startet die offizielle Simulation mit einem Code, den man mit Freunden teilen kann.
Future<void> startSharedExam(BuildContext context, int code) {
  final app = context.read<AppState>();
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ExamScreen(
      config: ExamConfig(
        questions: app.builder.officialExam(code: code),
        limitSec: AppConfig.examMinutes * 60,
        maxErrors: AppConfig.examMaxErrors,
        official: true,
        immediate: app.settings.examImmediateFeedback,
      ),
    ),
  ));
}

class ShareExamCard extends StatelessWidget {
  const ShareExamCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.tr('Prüfung mit Freunden', 'Esame con gli amici'),
      trailing: const Icon(Icons.group_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr(
            'Mit demselben Code bekommt jeder genau dieselben 30 Fragen – danach könnt ihr eure Fehler vergleichen.',
            'Con lo stesso codice tutti ricevono le stesse 30 domande – poi potete confrontare gli errori.',
          )),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _createCode(context),
                icon: const Icon(Icons.share_outlined),
                label: Text(context.tr('Code erstellen', 'Crea codice')),
              ),
              OutlinedButton.icon(
                onPressed: () => _enterCode(context),
                icon: const Icon(Icons.pin_outlined),
                label: Text(context.tr('Code eingeben', 'Inserisci codice')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createCode(BuildContext context) async {
    final code = newExamCode();
    final text = context.trNow(
      'Machst du mit? Führerschein Quiz Südtirol → Prüfung → „Code eingeben“: $code',
      'Ci stai? Quiz Patente Alto Adige → Esame → „Inserisci codice“: $code',
    );
    final start = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.trNow('Dein Prüfungscode', 'Il tuo codice d\'esame')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText('$code', style: Theme.of(ctx).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 4)),
            const SizedBox(height: 12),
            Text(context.trNow('Schick den Code deinen Freunden. Alle mit derselben App-Version bekommen dieselben Fragen.',
                'Invia il codice ai tuoi amici. Con la stessa versione dell\'app ricevono le stesse domande.')),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trNow('Kopiert', 'Copiato'))));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(context.trNow('Kopieren', 'Copia')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.trNow('Jetzt starten', 'Inizia ora'))),
        ],
      ),
    );
    if (start == true && context.mounted) await startSharedExam(context, code);
  }

  Future<void> _enterCode(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final parsed = parseExamCode(controller.text);
        return AlertDialog(
          title: Text(context.trNow('Prüfungscode eingeben', 'Inserisci il codice')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: '123456', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (parsed != null) Navigator.pop(ctx, parsed);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.trNow('Abbrechen', 'Annulla'))),
            FilledButton(
              onPressed: parsed == null ? null : () => Navigator.pop(ctx, parsed),
              child: Text(context.trNow('Starten', 'Inizia')),
            ),
          ],
        );
      }),
    );
    if (code != null && context.mounted) await startSharedExam(context, code);
  }
}

// ---------- Erfolge und Abzeichen ----------

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final Set<String> _seenBefore = {...context.read<AppState>().local.seenAchievements};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final unlocked = achievements(app.progress, app.bank).where((a) => a.unlocked).map((a) => a.id).toList();
      app.updateLocal((l) => l.seenAchievements = unlocked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = achievements(app.progress, app.bank);
    final theme = Theme.of(context);
    final unlocked = list.where((a) => a.unlocked).length;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Erfolge ($unlocked/${list.length})', 'Traguardi ($unlocked/${list.length})'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 700 ? 3 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: cols == 3 ? 1.1 : 0.8,
                children: [
                  for (final a in list)
                    Card(
                      margin: EdgeInsets.zero,
                      color: a.unlocked ? theme.colorScheme.secondaryContainer : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Opacity(opacity: a.unlocked ? 1 : 0.3, child: Text(a.emoji, style: const TextStyle(fontSize: 36))),
                            const SizedBox(height: 6),
                            Text(a.title(app.italianUi),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            if (a.unlocked && !_seenBefore.contains(a.id))
                              Text(context.tr('NEU', 'NUOVO'), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                            const SizedBox(height: 4),
                            Text(a.description(app.italianUi),
                                textAlign: TextAlign.center, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                            if (!a.unlocked) ...[
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: a.progress, minHeight: 4),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Hinweis auf der Startseite, wenn neue Abzeichen freigeschaltet wurden.
class NewAchievementsBanner extends StatelessWidget {
  const NewAchievementsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final seen = app.local.seenAchievements.toSet();
    final fresh = achievements(app.progress, app.bank).where((a) => a.unlocked && !seen.contains(a.id)).toList();
    if (fresh.isEmpty) return const SizedBox.shrink();
    final first = fresh.first;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(first.emoji, style: const TextStyle(fontSize: 28)),
        title: Text(fresh.length == 1
            ? context.tr('Neues Abzeichen: ${first.title(false)}', 'Nuovo traguardo: ${first.title(true)}')
            : context.tr('${fresh.length} neue Abzeichen!', '${fresh.length} nuovi traguardi!')),
        subtitle: Text(first.description(app.italianUi)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AchievementsScreen())),
      ),
    );
  }
}

// ---------- Fehlerbericht ----------

/// Öffnet ein vorausgefülltes GitHub-Issue für eine Frage („Erklärung unklar oder falsch“).
Future<void> reportProblem(BuildContext context, Question q) async {
  final app = context.read<AppState>();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(context.trNow('Problem mit Frage ${q.id} melden', 'Segnala un problema con la domanda ${q.id}')),
      children: [
        for (final r in [
          (context.trNow('Erklärung unklar', 'Spiegazione poco chiara'), 'Erklärung unklar'),
          (context.trNow('Erklärung falsch', 'Spiegazione sbagliata'), 'Erklärung falsch'),
          (context.trNow('Übersetzung falsch', 'Traduzione sbagliata'), 'Übersetzung falsch'),
          (context.trNow('Bild passt nicht', 'La figura non corrisponde'), 'Bild passt nicht'),
          (context.trNow('Sonstiges', 'Altro'), 'Sonstiges'),
        ])
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r.$2), child: Text(r.$1)),
      ],
    ),
  );
  if (reason == null) return;
  final exp = app.bank.explanation(q, false);
  final body = StringBuffer()
    ..writeln('**Frage:** ${q.id} (Kapitel ${q.chapter.id}, Gruppe ${q.group.id})')
    ..writeln('**DE:** ${q.de}')
    ..writeln('**IT:** ${q.it}')
    ..writeln('**Offizielle Lösung:** ${q.answer ? 'RICHTIG' : 'FALSCH'}')
    ..writeln()
    ..writeln('**Erklärung in der App:** ${[exp.group, exp.question].whereType<String>().join(' ')}')
    ..writeln()
    ..writeln('**Was stimmt nicht?**')
    ..writeln('<!-- Bitte kurz beschreiben -->');
  final url = Uri.https('github.com', '/${AppConfig.githubOwner}/${AppConfig.githubRepo}/issues/new', {
    'title': '$reason: Frage ${q.id}',
    'body': body.toString(),
    'labels': 'erklaerung',
  });
  if (!await launchUrl(url, mode: LaunchMode.externalApplication) && context.mounted) {
    await Clipboard.setData(ClipboardData(text: body.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trNow('Text kopiert', 'Testo copiato'))));
    }
  }
}
