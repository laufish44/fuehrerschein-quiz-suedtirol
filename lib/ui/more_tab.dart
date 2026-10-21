import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'lexicon_screen.dart';
import 'question_list_screen.dart';
import 'settings_screen.dart';
import 'study_features_ui.dart';
import 'widgets.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final favorites = app.bank.questions.where(app.isFavorite).toList();
    final notes = app.notedQuestions;
    final hardest = app.progress.hardQuestions;
    final tricky = app.bank.trickyQuestions;

    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    final items = [
      (Icons.emoji_events_outlined, context.tr('Erfolge und Abzeichen', 'Traguardi e medaglie'),
          context.tr('Was du schon geschafft hast', 'Cosa hai già raggiunto'), () => open(const AchievementsScreen())),
      (Icons.traffic_outlined, context.tr('Prüfungsreif-Ampel', 'Semaforo di preparazione'),
          context.tr('Welche Kapitel noch Lücken haben', 'Quali capitoli hanno ancora lacune'), () => open(const ReadinessScreen())),
      (Icons.search, context.tr('Suche', 'Cerca'), context.tr('Alle Fragen durchsuchen', 'Cerca tra tutte le domande'),
          () => open(const SearchScreen())),
      (Icons.star_outline, context.tr('Favoriten', 'Preferite'), '${favorites.length}',
          () => open(QuestionListScreen(
                title: context.trNow('Favoriten', 'Preferite'),
                questions: favorites,
                emptyText: context.trNow('Markiere Fragen mit dem Stern, um sie hier zu sammeln.',
                    'Segna le domande con la stella per ritrovarle qui.'),
              ))),
      (Icons.sticky_note_2_outlined, context.tr('Notizen', 'Note'), '${notes.length}',
          () => open(QuestionListScreen(
                title: context.trNow('Notizen', 'Note'),
                questions: notes,
                emptyText: context.trNow('Noch keine Notizen.', 'Ancora nessuna nota.'),
              ))),
      (Icons.local_fire_department_outlined, context.tr('Meine schwierigen Fragen', 'Le mie domande difficili'), '${hardest.length}',
          () => open(QuestionListScreen(
                title: context.trNow('Meine schwierigen Fragen', 'Le mie domande difficili'),
                questions: hardest,
                emptyText: context.trNow('Noch keine schwierigen Fragen – hier landen Fragen, die du öfter falsch beantwortest.',
                    'Ancora nessuna – qui finiscono le domande che sbagli più spesso.'),
              ))),
      (Icons.psychology_alt_outlined, context.tr('Fallen-Fragen', 'Domande trabocchetto'),
          context.tr('${tricky.length} Aussagen, die einer mit gegenteiliger Lösung sehr ähnlich sind',
              '${tricky.length} affermazioni molto simili a una con soluzione opposta'),
          () => open(QuestionListScreen(title: context.trNow('Fallen-Fragen', 'Domande trabocchetto'), questions: tricky))),
      (Icons.signpost_outlined, context.tr('Verkehrszeichen-Lexikon', 'Lessico dei segnali'),
          context.tr('Alle Bilder mit richtigen und falschen Aussagen', 'Tutte le figure con affermazioni vere e false'),
          () => open(const LexiconScreen())),
      (Icons.settings_outlined, context.tr('Einstellungen', 'Impostazioni'), context.tr('Sprache, Lernen, Erinnerung, KI', 'Lingua, studio, promemoria, IA'),
          () => open(const SettingsScreen())),
      (Icons.cloud_sync_outlined, context.tr('Sync & Backup', 'Sincronizzazione e backup'), 'Google Drive · Export · Import',
          () => open(const SyncScreen())),
      (Icons.info_outline, context.tr('Updates & Info', 'Aggiornamenti e info'), '', () => open(const AboutScreen())),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          maxWidth: 760,
          child: Column(
            children: [
              for (final it in items)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    leading: Icon(it.$1),
                    title: Text(it.$2),
                    subtitle: it.$3.isEmpty ? null : Text(it.$3),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: it.$4,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
