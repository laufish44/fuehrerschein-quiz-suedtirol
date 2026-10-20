import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/progress.dart';
import '../data/question_bank.dart';
import '../data/session_builder.dart';
import 'lexicon_screen.dart';
import 'quiz_screen.dart';
import 'widgets.dart';

class LearnTab extends StatelessWidget {
  const LearnTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BigButton(
                      icon: Icons.shuffle,
                      label: context.tr('Alle Kapitel gemischt', 'Tutti i capitoli misti'),
                      onTap: () {
                        final all = [...app.bank.questions.where((q) => !p.isLearned(q))]..shuffle(Random());
                        startQuiz(context, context.trNow('Alle Kapitel gemischt', 'Tutti i capitoli'), all.take(app.settings.sessionSize).toList());
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BigButton(
                      icon: Icons.local_fire_department_outlined,
                      label: context.tr('Schwierige Fragen', 'Domande difficili'),
                      onTap: () => startQuiz(
                        context,
                        context.trNow('Schwierige Fragen', 'Domande difficili'),
                        app.builder.difficultSession(app.settings.sessionSize),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BigButton(
                      icon: Icons.image_outlined,
                      label: context.tr('Nach Bild lernen', 'Studia per figura'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LexiconScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('Kapitel wie im Theoriebuch', 'Capitoli come nel libro di teoria'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              for (final cs in p.chapters) _ChapterTile(stat: cs),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          minimumSize: const Size.fromHeight(76),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 13, height: 1.2)),
          ],
        ),
      );
}

class _ChapterTile extends StatelessWidget {
  final ChapterStat stat;
  const _ChapterTile({required this.stat});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final c = stat.chapter;
    final firstImage = c.groups.map((g) => g.image).whereType<String>().firstOrNull;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(chapter: c))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: firstImage != null
                    ? Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: Image.asset('assets/img/$firstImage.webp'),
                      )
                    : CircleAvatar(child: Text('${c.id}')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c.id}. ${c.name(app.italianUi)}', style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          LinearProgressIndicator(value: stat.seenRatio, minHeight: 6, color: theme.colorScheme.primary.withValues(alpha: 0.35)),
                          LinearProgressIndicator(value: stat.learnedRatio, minHeight: 6, color: correctColor, backgroundColor: Colors.transparent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        '${stat.learned}/${stat.total} gelernt · ${stat.seen} gesehen${stat.attempts > 0 ? ' · ${(stat.accuracy * 100).round()}% richtig' : ''}${stat.errors > 0 ? ' · ${stat.errors} Fehler' : ''}',
                        '${stat.learned}/${stat.total} imparate · ${stat.seen} viste${stat.attempts > 0 ? ' · ${(stat.accuracy * 100).round()}% corrette' : ''}${stat.errors > 0 ? ' · ${stat.errors} errori' : ''}',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Kapitel: Übungsmodi und alle Fragengruppen.
class ChapterScreen extends StatelessWidget {
  final Chapter chapter;
  const ChapterScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final b = app.builder;
    final theme = Theme.of(context);
    final cs = p.chapterStat(chapter);
    final name = chapter.name(app.italianUi);
    final size = app.settings.sessionSize;
    final hardCount = chapter.questions.where(p.isHard).length;

    void go(String title, List<Question> qs) => startQuiz(context, title, qs);

    final modes = [
      (Icons.local_fire_department_outlined, context.tr('Schwierige Fragen', 'Domande difficili'), hardCount == 0 ? null : hardCount,
          () => go('$name – ${context.trNow('schwierig', 'difficili')}', b.difficultSession(size, chapter: chapter))),
      (Icons.format_list_numbered, context.tr('Alle der Reihe nach', 'Tutte in ordine'), chapter.questions.length,
          () => go(name, b.chapterQuestions(chapter, QuestionFilter.all))),
      (Icons.shuffle, context.tr('Zufällig ($size)', 'Casuali ($size)'), null,
          () => go(name, b.chapterQuestions(chapter, QuestionFilter.all, shuffle: true).take(size).toList())),
      (Icons.fiber_new_outlined, context.tr('Nur neue', 'Solo nuove'), chapter.questions.length - cs.seen,
          () => go(name, b.chapterQuestions(chapter, QuestionFilter.unseen, shuffle: true))),
      (Icons.school_outlined, context.tr('Noch nicht gelernt', 'Non ancora imparate'), chapter.questions.length - cs.learned,
          () => go(name, b.chapterQuestions(chapter, QuestionFilter.notLearned, shuffle: true))),
      (Icons.error_outline, context.tr('Nur Fehler', 'Solo errori'), cs.errors,
          () => go(name, b.chapterQuestions(chapter, QuestionFilter.errors, shuffle: true))),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('${chapter.id}. $name', maxLines: 2)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (app.settings.showSecondLanguage || app.italianUi != app.italianQuestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(chapter.name(!app.italianUi), style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                  ),
                SectionCard(
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 12,
                    children: [
                      StatTile(value: '${cs.learned}/${cs.total}', label: context.tr('gelernt', 'imparate'), icon: Icons.check_circle, color: correctColor),
                      StatTile(value: '${cs.seen}', label: context.tr('gesehen', 'viste'), icon: Icons.visibility_outlined),
                      StatTile(value: cs.attempts == 0 ? '–' : '${(cs.accuracy * 100).round()}%', label: context.tr('Trefferquote', 'precisione'), icon: Icons.percent),
                      StatTile(value: '${cs.errors}', label: context.tr('Fehler', 'errori'), icon: Icons.error_outline, color: cs.errors > 0 ? wrongColor : null),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final m in modes)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      leading: Icon(m.$1),
                      title: Text(m.$2),
                      trailing: m.$3 == null ? const Icon(Icons.play_arrow) : Text('${m.$3}', style: theme.textTheme.titleMedium),
                      enabled: m.$3 == null || m.$3! > 0,
                      onTap: m.$4,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(context.tr('Fragengruppen (${chapter.groups.length})', 'Gruppi di domande (${chapter.groups.length})'),
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  context.tr('Jede Gruppe gehört zu einem Bild oder Thema – ideal, um alle Varianten einer Frage zu lernen.',
                      'Ogni gruppo riguarda una figura o un tema – ideale per imparare tutte le varianti.'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final g in chapter.groups) GroupTile(group: g),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GroupTile extends StatelessWidget {
  final QuestionGroup group;
  const GroupTile({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final learned = group.questions.where(p.isLearned).length;
    final errors = group.questions.where(p.isError).length;
    final first = group.questions.first;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: group.image != null
            ? Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Image.asset('assets/img/${group.image}.webp'),
              )
            : const SizedBox(width: 52, child: Icon(Icons.notes)),
        title: Text(first.text(app.italianQuestions), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(context.tr(
          '${group.questions.length} Aussagen · $learned gelernt${errors > 0 ? ' · $errors Fehler' : ''}',
          '${group.questions.length} affermazioni · $learned imparate${errors > 0 ? ' · $errors errori' : ''}',
        )),
        trailing: SizedBox(
          width: 36,
          child: ProgressRing(value: learned / group.questions.length, size: 30, stroke: 4, color: correctColor),
        ),
        onTap: () => startQuiz(context, context.trNow('Gruppe ${group.id}', 'Gruppo ${group.id}'), [...group.questions]..shuffle(Random())),
      ),
    );
  }
}
