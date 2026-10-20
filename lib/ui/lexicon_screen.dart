import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/question_bank.dart';
import 'quiz_screen.dart';
import 'widgets.dart';

/// Alle Verkehrszeichen und Bilder der Prüfung, mit den zugehörigen Aussagen.
class LexiconScreen extends StatefulWidget {
  const LexiconScreen({super.key});

  @override
  State<LexiconScreen> createState() => _LexiconScreenState();
}

class _LexiconScreenState extends State<LexiconScreen> {
  int? _chapter;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final entries = app.bank.imageEntries();
    final chapterIds = {for (final e in entries) e.questions.first.chapter.id}.toList()..sort();
    final shown = _chapter == null ? entries : entries.where((e) => e.questions.first.chapter.id == _chapter).toList();
    final p = app.progress;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Zeichen & Bilder (${entries.length})', 'Segnali e figure (${entries.length})'))),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(context.tr('Alle', 'Tutti')),
                    selected: _chapter == null,
                    onSelected: (_) => setState(() => _chapter = null),
                  ),
                ),
                for (final id in chapterIds)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$id. ${app.bank.chapter(id).name(app.italianUi)}'),
                      selected: _chapter == id,
                      onSelected: (_) => setState(() => _chapter = id),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final e = shown[i];
                final learned = e.questions.where(p.isLearned).length;
                return Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LexiconDetailScreen(image: e.image, questions: e.questions),
                    )),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            child: Image.asset('assets/img/${e.image}.webp'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: learned / e.questions.length,
                                    minHeight: 5,
                                    color: correctColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('${e.questions.length}', style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LexiconDetailScreen extends StatelessWidget {
  final String image;
  final List<Question> questions;
  const LexiconDetailScreen({super.key, required this.image, required this.questions});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final it = app.italianQuestions;
    final trueQs = questions.where((q) => q.answer).toList();
    final falseQs = questions.where((q) => !q.answer).toList();
    final groupExp = app.bank.explanation(questions.first, app.italianUi).group;

    Widget statement(Question q) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(q.answer ? Icons.check : Icons.close, size: 20, color: q.answer ? correctColor : wrongColor),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(q.text(it), style: theme.textTheme.bodyMedium?.copyWith(height: 1.35))),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(questions.first.chapter.name(app.italianUi))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: QuestionImage(asset: 'assets/img/$image.webp', size: 240)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => startQuiz(
                    context,
                    context.trNow('Bild üben', 'Esercitati sulla figura'),
                    [...questions]..shuffle(Random()),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(context.tr('Alle ${questions.length} Aussagen üben', 'Esercitati su tutte le ${questions.length}')),
                ),
                if (groupExp != null) ...[
                  const SizedBox(height: 12),
                  SectionCard(title: context.tr('Erklärung', 'Spiegazione'), child: Text(groupExp)),
                ],
                SectionCard(
                  title: context.tr('Das stimmt (${trueQs.length})', 'Vero (${trueQs.length})'),
                  child: Column(children: [for (final q in trueQs) statement(q)]),
                ),
                SectionCard(
                  title: context.tr('Das stimmt nicht – typische Fallen (${falseQs.length})', 'Falso – trappole tipiche (${falseQs.length})'),
                  child: Column(children: [for (final q in falseQs) statement(q)]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
