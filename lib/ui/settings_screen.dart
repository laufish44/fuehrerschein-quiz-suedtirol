import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/user_data.dart';
import '../services/ai_service.dart';
import '../services/drive_sync.dart';
import '../services/notification_service.dart';
import '../services/storage.dart';
import '../services/tts_service.dart';
import '../services/update_service.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final l = app.local;
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    void reschedule() => NotificationService.schedule(
          enabled: app.local.reminderEnabled,
          hour: app.local.reminderHour,
          minute: app.local.reminderMinute,
          italian: app.italianUi,
          examDate: app.settings.examDate,
        );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Einstellungen', 'Impostazioni'))),
      body: ListView(
        children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(context.tr('Sprache', 'Lingua')),
                ListTile(
                  title: Text(context.tr('App-Sprache', 'Lingua dell\'app')),
                  trailing: _LangSwitch(value: s.uiLanguage, onChanged: (v) => app.updateSettings((x) => x.uiLanguage = v)),
                ),
                ListTile(
                  title: Text(context.tr('Sprache der Fragen', 'Lingua delle domande')),
                  trailing: _LangSwitch(value: s.questionLanguage, onChanged: (v) => app.updateSettings((x) => x.questionLanguage = v)),
                ),
                SwitchListTile(
                  title: Text(context.tr('Zweite Sprache darunter anzeigen', 'Mostra anche l\'altra lingua')),
                  subtitle: Text(context.tr('Hilft, Fachbegriffe in beiden Sprachen zu lernen.', 'Aiuta a imparare i termini in entrambe le lingue.')),
                  value: s.showSecondLanguage,
                  onChanged: (v) => app.updateSettings((x) => x.showSecondLanguage = v),
                ),
                header(context.tr('Lernen', 'Studio')),
                SwitchListTile(
                  title: Text(context.tr('Übungen: Lösung sofort zeigen', 'Esercizi: soluzione subito')),
                  subtitle: Text(context.tr('Aus = Auflösung am Ende der Runde', 'Off = soluzioni alla fine')),
                  value: s.practiceImmediateFeedback,
                  onChanged: (v) => app.updateSettings((x) => x.practiceImmediateFeedback = v),
                ),
                SwitchListTile(
                  title: Text(context.tr('Prüfungen: Lösung sofort zeigen', 'Esami: soluzione subito')),
                  subtitle: Text(context.tr('Aus = wie bei der echten Prüfung erst am Ende', 'Off = alla fine, come all\'esame vero')),
                  value: s.examImmediateFeedback,
                  onChanged: (v) => app.updateSettings((x) => x.examImmediateFeedback = v),
                ),
                _SliderTile(
                  title: context.tr('Fragen pro Lernrunde', 'Domande per sessione'),
                  value: s.sessionSize,
                  min: 10,
                  max: 60,
                  divisions: 10,
                  onChanged: (v) => app.updateSettings((x) => x.sessionSize = v),
                ),
                _SliderTile(
                  title: context.tr('Tagesziel (Fragen)', 'Obiettivo giornaliero (domande)'),
                  value: s.dailyGoal,
                  min: 10,
                  max: 300,
                  divisions: 29,
                  onChanged: (v) => app.updateSettings((x) => x.dailyGoal = v),
                ),
                _SliderTile(
                  title: context.tr('„Gelernt“ nach so vielen Treffern in Folge', '„Imparata“ dopo risposte giuste di fila'),
                  value: s.learnedStreak,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) => app.updateSettings((x) => x.learnedStreak = v),
                ),
                _SliderTile(
                  title: context.tr('Raus aus „Meine Fehler“ nach so vielen Treffern', 'Fuori dagli errori dopo risposte giuste'),
                  value: s.errorClearStreak,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) => app.updateSettings((x) => x.errorClearStreak = v),
                ),
                ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(context.tr('Prüfungstermin', 'Data dell\'esame')),
                  subtitle: Text(s.examDate == null
                      ? context.tr('nicht festgelegt', 'non impostata')
                      : formatDate(DateTime.parse(s.examDate!))),
                  trailing: s.examDate == null
                      ? null
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () => app.updateSettings((x) => x.examDate = null)),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: s.examDate == null ? now.add(const Duration(days: 30)) : DateTime.parse(s.examDate!),
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 730)),
                    );
                    if (d != null) {
                      app.updateSettings((x) => x.examDate = dayKey(d));
                      reschedule();
                    }
                  },
                ),
                if (NotificationService.supported) ...[
                  header(context.tr('Erinnerung', 'Promemoria')),
                  SwitchListTile(
                    title: Text(context.tr('Tägliche Lern-Erinnerung', 'Promemoria giornaliero')),
                    value: l.reminderEnabled,
                    onChanged: (v) async {
                      if (v) await NotificationService.requestPermission();
                      app.updateLocal((x) => x.reminderEnabled = v);
                      reschedule();
                    },
                  ),
                  ListTile(
                    enabled: l.reminderEnabled,
                    leading: const Icon(Icons.alarm),
                    title: Text(context.tr('Uhrzeit', 'Ora')),
                    trailing: Text('${l.reminderHour.toString().padLeft(2, '0')}:${l.reminderMinute.toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleMedium),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: l.reminderHour, minute: l.reminderMinute),
                      );
                      if (t != null) {
                        app.updateLocal((x) {
                          x.reminderHour = t.hour;
                          x.reminderMinute = t.minute;
                        });
                        reschedule();
                      }
                    },
                  ),
                ],
                header(context.tr('Vorlesen', 'Lettura ad alta voce')),
                SwitchListTile(
                  title: Text(context.tr('Fragen automatisch vorlesen', 'Leggi automaticamente le domande')),
                  value: l.ttsAutoRead,
                  onChanged: (v) => app.updateLocal((x) => x.ttsAutoRead = v),
                ),
                ListTile(
                  title: Text(context.tr('Geschwindigkeit', 'Velocità')),
                  subtitle: Slider(
                    value: l.ttsRate,
                    min: 0.2,
                    max: 0.9,
                    onChanged: (v) => app.updateLocal((x) => x.ttsRate = v),
                    onChangeEnd: (v) => TtsService.speak(
                      app.italianQuestions ? 'Questa è la velocità di lettura.' : 'So schnell wird vorgelesen.',
                      italian: app.italianQuestions,
                      rate: v,
                    ),
                  ),
                ),
                header(context.tr('Darstellung', 'Aspetto')),
                ListTile(
                  title: Text(context.tr('Design', 'Tema')),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'system', icon: const Icon(Icons.brightness_auto), tooltip: context.tr('System', 'Sistema')),
                      ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode), tooltip: context.tr('Hell', 'Chiaro')),
                      ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode), tooltip: context.tr('Dunkel', 'Scuro')),
                    ],
                    selected: {l.themeMode},
                    onSelectionChanged: (v) => app.updateLocal((x) => x.themeMode = v.first),
                  ),
                ),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
                  SwitchListTile(
                    title: Text(context.tr('Tastatur-Hinweise anzeigen', 'Mostra scorciatoie da tastiera')),
                    value: l.keyboardHints,
                    onChanged: (v) => app.updateLocal((x) => x.keyboardHints = v),
                  ),
                header(context.tr('KI-Erklärungen', 'Spiegazioni IA')),
                ListTile(
                  title: Text(context.tr('Bevorzugter KI-Dienst', 'Servizio IA preferito')),
                  trailing: DropdownButton<String>(
                    value: s.aiService,
                    items: [for (final a in aiServices) DropdownMenuItem(value: a.id, child: Text(a.name))],
                    onChanged: (v) => app.updateSettings((x) => x.aiService = v ?? 'chatgpt'),
                  ),
                ),
                const _GeminiKeyTile(),
                header(context.tr('Daten', 'Dati')),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: Text(context.tr('Sync & Backup', 'Sincronizzazione e backup')),
                  subtitle: Text(context.tr('Google Drive, Export und Import', 'Google Drive, esporta e importa')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(context.tr('Updates & Info', 'Aggiornamenti e info')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
                ListTile(
                  leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
                  title: Text(context.tr('Lernstand zurücksetzen', 'Azzera i progressi'), style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.trNow('Wirklich alles zurücksetzen?', 'Azzerare davvero tutto?')),
                        content: Text(context.trNow(
                          'Alle Antworten, Prüfungen, Favoriten und Notizen werden gelöscht – auch auf deinen anderen Geräten, '
                              'wenn der Google-Drive-Sync aktiv ist.',
                          'Tutte le risposte, esami, preferiti e note verranno eliminati – anche sugli altri dispositivi se la '
                              'sincronizzazione è attiva.',
                        )),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.trNow('Abbrechen', 'Annulla'))),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.trNow('Zurücksetzen', 'Azzera')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) app.resetProgress();
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LangSwitch extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _LangSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'de', label: Text('Deutsch')),
          ButtonSegment(value: 'it', label: Text('Italiano')),
        ],
        selected: {value},
        onSelectionChanged: (v) => onChanged(v.first),
      );
}

class _SliderTile extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final ValueChanged<int> onChanged;
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        title: Row(children: [Expanded(child: Text(title)), Text('$value', style: Theme.of(context).textTheme.titleMedium)]),
        subtitle: Slider(
          value: value.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      );
}

class _GeminiKeyTile extends StatefulWidget {
  const _GeminiKeyTile();

  @override
  State<_GeminiKeyTile> createState() => _GeminiKeyTileState();
}

class _GeminiKeyTileState extends State<_GeminiKeyTile> {
  late final _key = TextEditingController(text: context.read<AppState>().local.geminiKey);
  late final _model = TextEditingController(text: context.read<AppState>().local.geminiModel);
  bool _visible = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
              'Optional: Mit deinem eigenen kostenlosen Gemini-API-Schlüssel kannst du direkt in der App mit der KI '
                  'chatten (das Bild der Frage wird mitgeschickt). Der Schlüssel bleibt nur auf diesem Gerät.',
              'Facoltativo: con la tua chiave API Gemini gratuita puoi chattare con l\'IA direttamente nell\'app '
                  '(viene inviata anche la figura). La chiave resta solo su questo dispositivo.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: !_visible,
            decoration: InputDecoration(
              labelText: context.tr('Gemini-API-Schlüssel', 'Chiave API Gemini'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
            onChanged: (v) => app.updateLocal((x) => x.geminiKey = v.trim()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: context.tr('Modell (leer = ${AppConfig.defaultGeminiModel})', 'Modello (vuoto = ${AppConfig.defaultGeminiModel})'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => app.updateLocal((x) => x.geminiModel = v.trim()),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(context.tr('Kostenlosen Schlüssel holen (Google AI Studio)', 'Ottieni una chiave gratuita (Google AI Studio)')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google-Drive-Sync sowie Export/Import einer Sicherungsdatei.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sync = context.watch<DriveSync>();
    final theme = Theme.of(context);
    final last = sync.lastSync;

    Future<void> export() async {
      final bytes = Uint8List.fromList(utf8.encode(app.exportJson()));
      final name = 'fuehrerschein-quiz-backup-${dayKey(DateTime.now())}.json';
      try {
        final path = await FilePicker.saveFile(
          dialogTitle: context.trNow('Sicherung speichern', 'Salva backup'),
          fileName: name,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
        if (path != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trNow('Gespeichert.', 'Salvato.'))));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ $e')));
        }
      }
    }

    Future<void> import() async {
      try {
        final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
        final bytes = res?.files.single.bytes;
        if (bytes == null) return;
        final changed = app.importJson(utf8.decode(bytes));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(changed
                ? context.trNow('Sicherung eingespielt und mit deinem Stand zusammengeführt.', 'Backup importato e unito ai tuoi dati.')
                : context.trNow('Nichts Neues in der Datei.', 'Niente di nuovo nel file.')),
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.trNow('Datei konnte nicht gelesen werden: $e', 'Impossibile leggere il file: $e')),
          ));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Sync & Backup', 'Sincronizzazione e backup'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: 'Google Drive',
                  trailing: Icon(
                    sync.connected ? Icons.cloud_done : Icons.cloud_off,
                    color: sync.connected ? correctColor : theme.colorScheme.outline,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(context.tr(
                        'Dein Lernstand wird als Datei in einem versteckten App-Ordner deines Google Drive gespeichert und '
                            'bei jedem App-Start sowie nach jeder Lernrunde abgeglichen – so lernst du am Handy und am PC weiter. '
                            'Die App sieht nur ihre eigene Datei, nicht den Rest deines Drives.',
                        'I tuoi progressi vengono salvati in una cartella nascosta dell\'app nel tuo Google Drive e sincronizzati '
                            'a ogni avvio e dopo ogni sessione – così continui su telefono e PC. L\'app vede solo il proprio file.',
                      )),
                      const SizedBox(height: 12),
                      if (!DriveSync.supported)
                        Text(
                          kIsWeb
                              ? context.tr('In der Browser-Version nicht verfügbar – nutze Export/Import.',
                                  'Non disponibile nella versione browser – usa esporta/importa.')
                              : context.tr('Der Google-Drive-Sync wird gerade eingerichtet und kommt mit einem Update.',
                                  'La sincronizzazione con Google Drive arriverà con un aggiornamento.'),
                          style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        )
                      else if (!sync.connected)
                        FilledButton.icon(
                          onPressed: sync.status == SyncStatus.syncing ? null : sync.connect,
                          icon: const Icon(Icons.login),
                          label: Text(context.tr('Mit Google verbinden', 'Collega a Google')),
                        )
                      else ...[
                        Text(
                          last == null
                              ? context.tr('Noch nicht synchronisiert.', 'Non ancora sincronizzato.')
                              : context.tr('Zuletzt synchronisiert: ${formatDate(last, withTime: true)}',
                                  'Ultima sincronizzazione: ${formatDate(last, withTime: true)}'),
                        ),
                        if (app.local.lastSyncError.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('⚠️ ${app.local.lastSyncError}', style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: sync.status == SyncStatus.syncing ? null : sync.syncNow,
                                icon: sync.status == SyncStatus.syncing
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.sync),
                                label: Text(context.tr('Jetzt synchronisieren', 'Sincronizza ora')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(onPressed: sync.disconnect, child: Text(context.tr('Trennen', 'Scollega'))),
                          ],
                        ),
                      ],
                      if (sync.status == SyncStatus.error && sync.error != null && !sync.connected)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('⚠️ ${sync.error}', style: TextStyle(color: theme.colorScheme.error)),
                        ),
                    ],
                  ),
                ),
                SectionCard(
                  title: context.tr('Sicherungsdatei', 'File di backup'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(context.tr(
                        'Exportiere deinen Lernstand als Datei, um ihn auf ein anderes Gerät zu übertragen. Beim Import wird '
                            'nichts überschrieben – beide Stände werden zusammengeführt.',
                        'Esporta i tuoi progressi in un file per trasferirli su un altro dispositivo. L\'importazione non '
                            'sovrascrive nulla: i dati vengono uniti.',
                      )),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: export,
                              icon: const Icon(Icons.upload_file),
                              label: Text(context.tr('Exportieren', 'Esporta')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: import,
                              icon: const Icon(Icons.download),
                              label: Text(context.tr('Importieren', 'Importa')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                FutureBuilder<String>(
                  future: Storage.location(),
                  builder: (context, snap) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${context.tr('Gespeichert in', 'Salvato in')}: ${snap.data ?? '…'}\n'
                      '${app.data.totalEvents} ${context.tr('Antworten', 'risposte')} · ${app.data.exams.length} ${context.tr('Prüfungen', 'esami')}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
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

/// Version, Updates, Quellen.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final u = context.watch<UpdateService>();
    final theme = Theme.of(context);

    String statusText() => switch (u.status) {
          UpdateStatus.idle => '',
          UpdateStatus.checking => context.tr('Suche nach Updates…', 'Ricerca aggiornamenti…'),
          UpdateStatus.upToDate => context.tr('Du hast die neueste Version.', 'Hai l\'ultima versione.'),
          UpdateStatus.available => context.tr('Version ${u.release?.version} ist verfügbar.', 'È disponibile la versione ${u.release?.version}.'),
          UpdateStatus.downloading => context.tr('Lade… ${(u.progress * 100).round()}%', 'Download… ${(u.progress * 100).round()}%'),
          UpdateStatus.ready => context.tr('Bereit zur Installation.', 'Pronto per l\'installazione.'),
          UpdateStatus.installing => context.tr('Wird installiert…', 'Installazione…'),
          UpdateStatus.error => '⚠️ ${u.error}',
        };

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Updates & Info', 'Aggiornamenti e info'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Image.asset('assets/icon/icon.png', width: 96, height: 96)),
                const SizedBox(height: 8),
                Center(child: Text(AppConfig.appName, style: theme.textTheme.titleLarge)),
                Center(child: Text('Version ${u.currentVersion}', style: theme.textTheme.bodyMedium)),
                const SizedBox(height: 16),
                if (u.supported)
                  SectionCard(
                    title: 'Updates',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.tr('Automatisch aktualisieren', 'Aggiorna automaticamente')),
                          subtitle: Text(defaultTargetPlatform == TargetPlatform.android
                              ? context.tr('Neue Versionen werden geladen; du bestätigst nur noch „Installieren“.',
                                  'Le nuove versioni vengono scaricate; confermi solo „Installa“.')
                              : context.tr('Neue Versionen werden im Hintergrund installiert, die App startet neu.',
                                  'Le nuove versioni si installano in background e l\'app si riavvia.')),
                          value: app.local.autoUpdate,
                          onChanged: (v) => app.updateLocal((x) => x.autoUpdate = v),
                        ),
                        if (statusText().isNotEmpty) Text(statusText()),
                        if (u.status == UpdateStatus.downloading) LinearProgressIndicator(value: u.progress),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: u.status == UpdateStatus.checking || u.status == UpdateStatus.downloading ? null : u.check,
                              icon: const Icon(Icons.refresh),
                              label: Text(context.tr('Nach Updates suchen', 'Cerca aggiornamenti')),
                            ),
                            if (u.status == UpdateStatus.available)
                              FilledButton.icon(
                                onPressed: () async {
                                  if (await u.download()) await u.install();
                                },
                                icon: const Icon(Icons.download),
                                label: Text(context.tr('Jetzt aktualisieren', 'Aggiorna ora')),
                              ),
                            if (u.status == UpdateStatus.ready)
                              FilledButton.icon(
                                onPressed: u.install,
                                icon: const Icon(Icons.system_update),
                                label: Text(context.tr('Installieren', 'Installa')),
                              ),
                          ],
                        ),
                        if (u.release != null && u.release!.notes.isNotEmpty && u.status != UpdateStatus.upToDate) ...[
                          const SizedBox(height: 8),
                          Text(context.tr('Neu in ${u.release!.version}:', 'Novità in ${u.release!.version}:'), style: theme.textTheme.titleSmall),
                          Text(u.release!.notes),
                        ],
                      ],
                    ),
                  ),
                SectionCard(
                  title: context.tr('Über die App', 'Informazioni'),
                  child: Text(context.tr(
                    'Enthält alle ${app.bank.questions.length} Aussagen der Ministeriumsliste für die Führerscheine A und B '
                        '(Stand der PDF „${app.bank.source}“) auf Deutsch und Italienisch. Die Erklärungen wurden mit KI '
                        'erstellt und können Fehler enthalten – maßgeblich ist immer die offizielle Lösung.\n\n'
                        'Kein offizielles Angebot des Ministeriums oder der Provinz Bozen.',
                    'Contiene tutte le ${app.bank.questions.length} affermazioni del listato ministeriale per le patenti A e B '
                        'in tedesco e italiano. Le spiegazioni sono state create con l\'IA e possono contenere errori – vale sempre '
                        'la soluzione ufficiale.\n\nNon è un servizio ufficiale del Ministero o della Provincia di Bolzano.',
                  )),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(context.tr('Quellcode & Downloads auf GitHub', 'Codice e download su GitHub')),
                  subtitle: const Text(AppConfig.githubUrl),
                  onTap: () => launchUrl(Uri.parse(AppConfig.githubUrl), mode: LaunchMode.externalApplication),
                ),
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: Text(context.tr('Alle Versionen', 'Tutte le versioni')),
                  onTap: () => launchUrl(Uri.parse('${AppConfig.githubUrl}/releases'), mode: LaunchMode.externalApplication),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(context.tr('Lizenzen', 'Licenze')),
                  onTap: () => showLicensePage(context: context, applicationName: AppConfig.appName, applicationVersion: u.currentVersion),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
