import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/question_bank.dart';
import 'explanation.dart';
import 'quiz_screen.dart';
import 'widgets.dart';

/// Liste von Fragen (Favoriten, Notizen, schwierigste …) mit Übungs-Knopf.
class QuestionListScreen extends StatelessWidget {
  final String title;
  final List<Question> questions;
  final String? emptyText;
  const QuestionListScreen({super.key, required this.title, required this.questions, this.emptyText});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (questions.isNotEmpty)
            TextButton.icon(
              onPressed: () => startQuiz(context, title, [...questions]..shuffle()),
              icon: const Icon(Icons.play_arrow),
              label: Text(context.tr('Üben', 'Esercitati')),
            ),
        ],
      ),
      body: questions.isEmpty
          ? EmptyState(icon: Icons.inbox_outlined, text: emptyText ?? context.tr('Nichts hier.', 'Niente qui.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: questions.length,
              itemBuilder: (context, i) => ContentWidth(child: QuestionRow(question: questions[i])),
            ),
    );
  }
}

class QuestionRow extends StatelessWidget {
  final Question question;
  const QuestionRow({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final note = app.note(question);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: question.imageAsset != null
            ? Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                child: Image.asset(question.imageAsset!),
              )
            : SizedBox(width: 48, child: Center(child: questionStatusIcon(context, question))),
        title: Text(question.text(app.italianQuestions), maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${question.answer ? context.tr('RICHTIG', 'VERO') : context.tr('FALSCH', 'FALSO')} · Nr. ${question.id}'
          '${note.isNotEmpty ? '\n📝 $note' : ''}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: question.imageAsset != null ? questionStatusIcon(context, question) : null,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuestionDetailScreen(question: question))),
      ),
    );
  }
}

/// Einzelne Frage mit Lösung, Erklärung, Statistik und Notiz.
class QuestionDetailScreen extends StatelessWidget {
  final Question question;
  const QuestionDetailScreen({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final s = app.progress.stat(question);
    final note = app.note(question);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Frage ${question.id}', 'Domanda ${question.id}'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${question.chapter.id}. ${question.chapter.name(app.italianUi)}', style: theme.textTheme.labelLarge),
                QuestionToolbar(question: question),
                if (question.imageAsset != null) Center(child: QuestionImage(asset: question.imageAsset!, size: 220)),
                const SizedBox(height: 12),
                QuestionText(question: question),
                const SizedBox(height: 16),
                ExplanationPanel(question: question),
                const SizedBox(height: 12),
                if (note.isNotEmpty)
                  SectionCard(
                    title: context.tr('Meine Notiz', 'La mia nota'),
                    onTap: () => editNote(context, question),
                    child: Text(note),
                  ),
                SectionCard(
                  title: context.tr('Deine Statistik', 'Le tue statistiche'),
                  child: s == null
                      ? Text(context.tr('Noch nie beantwortet.', 'Mai risposta.'))
                      : Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            StatTile(value: '${s.correct}', label: context.tr('richtig', 'corrette'), color: correctColor),
                            StatTile(value: '${s.wrong}', label: context.tr('falsch', 'sbagliate'), color: s.wrong > 0 ? wrongColor : null),
                            StatTile(value: '${s.streak}', label: context.tr('in Folge richtig', 'di fila')),
                            StatTile(
                              value: formatDate(DateTime.fromMillisecondsSinceEpoch(s.lastTs * 1000)),
                              label: context.tr('zuletzt', 'ultima volta'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => startQuiz(
                    context,
                    context.trNow('Gruppe ${question.group.id}', 'Gruppo ${question.group.id}'),
                    [...question.group.questions]..shuffle(),
                    immediate: true,
                  ),
                  icon: const Icon(Icons.layers_outlined),
                  label: Text(context.tr(
                    'Alle ${question.group.questions.length} Varianten dieser Frage üben',
                    'Esercitati su tutte le ${question.group.questions.length} varianti',
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Volltextsuche über alle Fragen (Deutsch und Italienisch) und Fragennummern.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Question> _results = [];
  String _query = '';

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final app = context.read<AppState>();
      final words = text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      setState(() {
        _query = text;
        _results = words.isEmpty
            ? []
            : app.bank.questions.where((q) => words.every(q.searchText.contains)).take(300).toList();
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: context.tr('Suchen (z. B. Schneeketten, 21810)…', 'Cerca (es. catene, 21810)…'),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              tooltip: context.tr('Treffer üben', 'Esercitati sui risultati'),
              icon: const Icon(Icons.play_arrow),
              onPressed: () => startQuiz(context, '„$_query“', _results),
            ),
        ],
      ),
      body: _query.isEmpty
          ? EmptyState(icon: Icons.search, text: context.tr('Durchsucht alle 7.020 Fragen auf Deutsch und Italienisch.',
              'Cerca tra tutte le 7.020 domande in tedesco e italiano.'))
          : _results.isEmpty
              ? EmptyState(icon: Icons.search_off, text: context.tr('Keine Treffer.', 'Nessun risultato.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _results.length + 1,
                  itemBuilder: (context, i) => i == 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(context.tr('${_results.length}${_results.length == 300 ? '+' : ''} Treffer',
                              '${_results.length}${_results.length == 300 ? '+' : ''} risultati')),
                        )
                      : ContentWidth(child: QuestionRow(question: _results[i - 1])),
                ),
    );
  }
}
