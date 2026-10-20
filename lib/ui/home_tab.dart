import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/update_service.dart';
import 'exam_screen.dart';
import 'learn_tab.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final theme = Theme.of(context);
    final pass = p.passProbability();
    final today = p.today();
    final goal = app.settings.dailyGoal;
    final streak = p.dayStreak;
    final due = p.dueQuestions().length;
    final errors = p.errorQuestions.length;
    final hard = p.hardQuestions.length;
    final weakest = ([...p.chapters]..sort((a, b) => a.knowledge.compareTo(b.knowledge))).first;
    final recent = p.recentOfficialExams(5);

    int? daysLeft;
    if (app.settings.examDate != null) {
      final d = DateTime.tryParse(app.settings.examDate!);
      if (d != null) {
        final now = DateTime.now();
        daysLeft = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
      }
    }

    final readinessText = pass >= 0.9
        ? context.tr('Prüfungsreif! 🎉', 'Pronto per l\'esame! 🎉')
        : pass >= 0.6
            ? context.tr('Fast geschafft', 'Quasi pronto')
            : pass >= 0.2
                ? context.tr('Auf gutem Weg', 'Sulla buona strada')
                : context.tr('Noch am Anfang', 'Agli inizi');

    final actions = <_Action>[
      _Action(Icons.auto_awesome, context.tr('Intelligent lernen', 'Studio intelligente'),
          context.tr('Wiederholung + neue Fragen', 'Ripasso + domande nuove'), theme.colorScheme.primary, () {
        startQuiz(context, context.trNow('Intelligent lernen', 'Studio intelligente'), app.builder.smartSession(app.settings.sessionSize));
      }),
      _Action(Icons.assignment_turned_in_outlined, context.tr('Prüfung simulieren', 'Simula l\'esame'),
          context.tr('30 Fragen · 20 Min', '30 domande · 20 min'), const Color(0xFF6A1B9A), () => startOfficialExam(context)),
      _Action(Icons.error_outline, context.tr('Meine Fehler', 'I miei errori'), '$errors', wrongColor, () {
        startQuiz(context, context.trNow('Meine Fehler', 'I miei errori'), p.errorQuestions..shuffle(Random()), immediate: true);
      }),
      _Action(Icons.local_fire_department_outlined, context.tr('Schwierige Fragen', 'Domande difficili'),
          hard > 0 ? context.tr('$hard persönlich schwierig', '$hard difficili per te') : context.tr('Typische Fallen', 'Trappole tipiche'),
          Colors.deepOrange, () {
        startQuiz(context, context.trNow('Schwierige Fragen', 'Domande difficili'), app.builder.difficultSession(app.settings.sessionSize));
      }),
      _Action(Icons.history, context.tr('Wiederholen', 'Ripasso'), context.tr('$due fällig', '$due da ripassare'),
          const Color(0xFF00838F), () {
        startQuiz(context, context.trNow('Wiederholen', 'Ripasso'), p.dueQuestions().take(app.settings.sessionSize * 2).toList());
      }),
      _Action(Icons.shuffle, context.tr('Zufällige Fragen', 'Domande casuali'), context.tr('aus allen Kapiteln', 'da tutti i capitoli'),
          const Color(0xFFEF6C00), () {
        final all = [...app.bank.questions]..shuffle(Random());
        startQuiz(context, context.trNow('Zufällige Fragen', 'Domande casuali'), all.take(app.settings.sessionSize).toList());
      }),
      _Action(Icons.trending_down, context.tr('Schwächstes Kapitel', 'Capitolo più debole'),
          '${weakest.chapter.id}. ${weakest.chapter.name(app.italianUi)}', const Color(0xFF5D4037), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(chapter: weakest.chapter)));
      }),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _UpdateBanner(),
              SectionCard(
                child: Row(
                  children: [
                    ProgressRing(
                      value: pass,
                      size: 110,
                      stroke: 12,
                      color: scoreColor(pass),
                      center: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(pass * 100).round()}%', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(context.tr('Bestehen', 'Promozione'), style: theme.textTheme.labelSmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('Prüfungsreife', 'Preparazione'), style: theme.textTheme.labelLarge),
                          Text(readinessText, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(context.tr('${p.learnedCount} von ${app.bank.questions.length} gelernt',
                              '${p.learnedCount} di ${app.bank.questions.length} imparate')),
                          Text(context.tr('${p.seenCount} gesehen · ${(p.accuracy * 100).round()}% richtig',
                              '${p.seenCount} viste · ${(p.accuracy * 100).round()}% corrette')),
                          if (recent.total > 0)
                            Text(context.tr('Simulationen: ${recent.passed}/${recent.total} bestanden',
                                'Simulazioni: ${recent.passed}/${recent.total} superate')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.flag_outlined, size: 18),
                              const SizedBox(width: 6),
                              Text(context.tr('Tagesziel', 'Obiettivo'), style: theme.textTheme.labelLarge),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${today.answered} / $goal', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: goal == 0 ? 0 : min(1, today.answered / goal),
                              minHeight: 8,
                              color: today.answered >= goal ? correctColor : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.local_fire_department, size: 18, color: streak > 0 ? Colors.deepOrange : null),
                              const SizedBox(width: 6),
                              Text(context.tr('Serie', 'Serie'), style: theme.textTheme.labelLarge),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(context.tr('$streak ${streak == 1 ? 'Tag' : 'Tage'}', '$streak ${streak == 1 ? 'giorno' : 'giorni'}'),
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                            daysLeft == null
                                ? context.tr('Prüfungstermin festlegen', 'Imposta data esame')
                                : daysLeft >= 0
                                    ? context.tr('Prüfung in $daysLeft Tagen', 'Esame tra $daysLeft giorni')
                                    : context.tr('Prüfungstermin vorbei', 'Data esame passata'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 700 ? 3 : 2;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: cols == 3 ? 2.2 : 1.45,
                  children: [for (final a in actions) _ActionCard(action: a)],
                );
              }),
              if (app.bank.explainedCount < app.bank.questions.length) ...[
                const SizedBox(height: 12),
                Text(
                  context.tr(
                    'Offline-Erklärungen: ${app.bank.explainedCount} von ${app.bank.questions.length} – weitere kommen per Update.',
                    'Spiegazioni offline: ${app.bank.explainedCount} di ${app.bank.questions.length} – altre in arrivo con gli aggiornamenti.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Action {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  _Action(this.icon, this.title, this.subtitle, this.color, this.onTap);
}

class _ActionCard extends StatelessWidget {
  final _Action action;
  const _ActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: action.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(action.icon, color: action.color),
              ),
              const Spacer(),
              Text(action.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(action.subtitle, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hinweis auf verfügbare/bereite Updates.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    if (kIsWeb) return const SizedBox.shrink();
    final r = u.release;
    String? text;
    Widget? action;
    switch (u.status) {
      case UpdateStatus.available:
        text = context.tr('Version ${r?.version} ist verfügbar.', 'È disponibile la versione ${r?.version}.');
        action = TextButton(onPressed: () => u.download().then((ok) { if (ok) u.install(); }), child: Text(context.tr('Laden', 'Scarica')));
      case UpdateStatus.downloading:
        text = context.tr('Update wird geladen… ${(u.progress * 100).round()}%', 'Download aggiornamento… ${(u.progress * 100).round()}%');
      case UpdateStatus.ready:
        text = context.tr('Version ${r?.version} ist bereit.', 'La versione ${r?.version} è pronta.');
        action = FilledButton(onPressed: u.install, child: Text(context.tr('Installieren', 'Installa')));
      case UpdateStatus.installing:
        text = context.tr('Update wird installiert…', 'Installazione in corso…');
      default:
        return const SizedBox.shrink();
    }
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.system_update),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Wird von main.dart genutzt, um den App-Namen zu zeigen.
String appTitle(bool italian) => italian ? 'Quiz Patente Alto Adige' : AppConfig.appName;
