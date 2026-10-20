import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config.dart';
import 'exam_screen.dart';
import 'widgets.dart';

class ExamTab extends StatelessWidget {
  const ExamTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final theme = Theme.of(context);
    final exams = p.exams;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.assignment_turned_in, color: theme.colorScheme.onPrimaryContainer, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(context.tr('Offizielle Prüfungssimulation', 'Simulazione d\'esame ufficiale'),
                                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr(
                          '${AppConfig.examQuestions} Fragen aus allen 25 Kapiteln · ${AppConfig.examMinutes} Minuten · '
                              'bestanden mit höchstens ${AppConfig.examMaxErrors} Fehlern. Die Auflösung gibt es am Ende – '
                              'wie bei der echten Prüfung.',
                          '${AppConfig.examQuestions} domande da tutti i 25 capitoli · ${AppConfig.examMinutes} minuti · '
                              'superato con massimo ${AppConfig.examMaxErrors} errori. Le soluzioni alla fine – come all\'esame vero.',
                        ),
                        style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: () => startOfficialExam(context),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(context.tr('Prüfung starten', 'Inizia l\'esame')),
                      ),
                    ],
                  ),
                ),
              ),
              SectionCard(
                title: context.tr('Eigenes Quiz', 'Quiz personalizzato'),
                trailing: const Icon(Icons.tune),
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const CustomQuizSheet(),
                ),
                child: Text(context.tr(
                  'Anzahl, Zeit, erlaubte Fehler und Kapitel selbst wählen – z. B. nur Fehler oder nur Verkehrszeichen.',
                  'Scegli numero, tempo, errori ammessi e capitoli – ad es. solo errori o solo segnali.',
                )),
              ),
              const SizedBox(height: 12),
              Text(context.tr('Verlauf (${exams.length})', 'Cronologia (${exams.length})'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (exams.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.tr('Noch keine Prüfung gemacht.', 'Ancora nessun esame svolto.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              for (final x in exams)
                Builder(builder: (context) {
                  final errors = p.examErrors(x);
                  final passed = errors <= x.maxErrors;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: passed ? correctColor : wrongColor,
                        foregroundColor: Colors.white,
                        child: Text('$errors'),
                      ),
                      title: Text(
                        '${passed ? context.tr('Bestanden', 'Superato') : context.tr('Nicht bestanden', 'Non superato')}'
                        ' · ${x.official ? context.tr('Simulation', 'Simulazione') : context.tr('Eigenes Quiz', 'Quiz')}',
                      ),
                      subtitle: Text(
                        '${formatDate(DateTime.fromMillisecondsSinceEpoch(x.start * 1000), withTime: true)} · '
                        '${x.qids.length} ${context.tr('Fragen', 'domande')} · ${formatClock(x.durationSec)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamResultScreen(record: x))),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
