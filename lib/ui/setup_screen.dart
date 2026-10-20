import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../data/user_data.dart';
import '../services/ai_service.dart';
import '../services/drive_sync.dart';
import 'widgets.dart';

enum SetupStep { welcome, drive, gemini }

/// Welche Einrichtungsschritte noch anstehen (beim ersten Start alle, nach Updates nur neue).
List<SetupStep> pendingSetupSteps(AppState app, DriveSync sync) => [
      if (!app.local.onboardingDone) SetupStep.welcome,
      if (DriveSync.supported && !app.local.drivePrompted && !sync.connected) SetupStep.drive,
      // Vor Einrichtung des Drive-Syncs zeigen wir den Schritt nur beim allerersten Start (als Ausblick).
      if (!DriveSync.supported && !app.local.onboardingDone && !kIsWeb) SetupStep.drive,
      if (!app.local.geminiPrompted && app.local.geminiKey.isEmpty) SetupStep.gemini,
    ];

/// Einrichtung beim ersten Start: Sprache, Prüfungstermin, Google Drive, Gemini.
class SetupScreen extends StatefulWidget {
  final List<SetupStep> steps;
  const SetupScreen({super.key, required this.steps});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pages = PageController();
  int _page = 0;
  DateTime? _examDate;
  int _goal = 60;
  final _key = TextEditingController();
  String? _keyStatus;
  bool _testing = false;

  @override
  void dispose() {
    _pages.dispose();
    _key.dispose();
    super.dispose();
  }

  void _markShown(SetupStep step) {
    final app = context.read<AppState>();
    switch (step) {
      case SetupStep.welcome:
        app.updateSettings((s) {
          s.dailyGoal = _goal;
          if (_examDate != null) s.examDate = dayKey(_examDate!);
        });
        app.updateLocal((l) => l.onboardingDone = true);
      case SetupStep.drive:
        if (DriveSync.supported) app.updateLocal((l) => l.drivePrompted = true);
      case SetupStep.gemini:
        app.updateLocal((l) {
          l.geminiPrompted = true;
          if (_key.text.trim().isNotEmpty) l.geminiKey = _key.text.trim();
        });
    }
  }

  void _next() {
    _markShown(widget.steps[_page]);
    if (_page >= widget.steps.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _testKey() async {
    final app = context.read<AppState>();
    setState(() {
      _testing = true;
      _keyStatus = null;
    });
    try {
      await AiService.testGeminiKey(_key.text, app.local.geminiModel);
      _keyStatus = app.italianUi ? '✅ La chiave funziona!' : '✅ Der Schlüssel funktioniert!';
    } catch (e) {
      _keyStatus = '⚠️ ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final it = app.italianUi;
    final last = _page >= widget.steps.length - 1;
    final step = widget.steps[_page];
    final skippable = step != SetupStep.welcome;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 560,
            child: Column(
              children: [
                if (widget.steps.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < widget.steps.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      for (final s in widget.steps)
                        switch (s) {
                          SetupStep.welcome => _welcome(context, app),
                          SetupStep.drive => _drive(context, app),
                          SetupStep.gemini => _gemini(context, app),
                        },
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      if (skippable)
                        TextButton(onPressed: _next, child: Text(it ? 'Salta' : 'Überspringen')),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                        onPressed: _next,
                        child: Text(last ? (it ? 'Iniziamo!' : 'Los geht\'s!') : (it ? 'Avanti' : 'Weiter')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageLayout({required IconData icon, required String title, required List<Widget> children, Widget? image}) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          image ?? Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context, AppState app) {
    final it = app.italianUi;
    final theme = Theme.of(context);
    return _pageLayout(
      icon: Icons.waving_hand,
      image: Image.asset('assets/icon/icon.png', width: 72, height: 72),
      title: it ? 'Benvenuto!' : 'Willkommen!',
      children: [
        Text(it
            ? 'Qui trovi tutte le 7.020 domande ufficiali per la patente A/B – in tedesco e italiano, ordinate per capitoli come nel libro di teoria.'
            : 'Hier findest du alle 7.020 offiziellen Prüfungsfragen für den Führerschein A/B – auf Deutsch und Italienisch, geordnet wie im Theoriebuch.'),
        const SizedBox(height: 20),
        Text(it ? 'Lingua' : 'Sprache', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'de', label: Text('Deutsch')),
            ButtonSegment(value: 'it', label: Text('Italiano')),
          ],
          selected: {app.settings.uiLanguage},
          onSelectionChanged: (v) => app.updateSettings((s) {
            s.uiLanguage = v.first;
            s.questionLanguage = v.first;
          }),
        ),
        const SizedBox(height: 20),
        Text(it ? 'Quando hai l\'esame?' : 'Wann ist deine Prüfung?', style: theme.textTheme.titleSmall),
        TextButton.icon(
          icon: const Icon(Icons.event),
          label: Text(_examDate == null ? (it ? 'Scegli data (facoltativo)' : 'Datum wählen (optional)') : formatDate(_examDate!)),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: now.add(const Duration(days: 30)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 730)),
            );
            if (d != null) setState(() => _examDate = d);
          },
        ),
        const SizedBox(height: 8),
        Text(it ? 'Obiettivo giornaliero: $_goal domande' : 'Tagesziel: $_goal Fragen', style: theme.textTheme.titleSmall),
        Slider(value: _goal.toDouble(), min: 20, max: 200, divisions: 18, label: '$_goal', onChanged: (v) => setState(() => _goal = v.round())),
      ],
    );
  }

  Widget _drive(BuildContext context, AppState app) {
    final it = app.italianUi;
    final sync = context.watch<DriveSync>();
    final theme = Theme.of(context);
    return _pageLayout(
      icon: Icons.cloud_sync_outlined,
      title: it ? 'Collega Google Drive' : 'Google Drive verbinden',
      children: [
        Text(it
            ? 'Accedi con il tuo account Google: i tuoi progressi vengono salvati in una cartella nascosta del TUO Google Drive e sincronizzati a ogni avvio – così continui su telefono e PC. L\'app vede solo il proprio file, nient\'altro del tuo Drive.'
            : 'Melde dich mit deinem eigenen Google-Konto an: Dein Lernstand wird in einem versteckten Ordner in DEINEM Google Drive gespeichert und bei jedem Start abgeglichen – so lernst du auf Handy und PC weiter. Die App sieht nur ihre eigene Datei, nichts anderes aus deinem Drive.'),
        const SizedBox(height: 20),
        if (!DriveSync.supported)
          Text(
            it
                ? 'La sincronizzazione arriva con un prossimo aggiornamento – te lo chiederemo di nuovo.'
                : 'Der Sync kommt mit einem der nächsten Updates – du wirst dann nochmal gefragt.',
            style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
          )
        else if (sync.connected)
          Row(
            children: [
              const Icon(Icons.check_circle, color: correctColor),
              const SizedBox(width: 8),
              Text(it ? 'Collegato!' : 'Verbunden!', style: theme.textTheme.titleMedium),
            ],
          )
        else ...[
          FilledButton.icon(
            onPressed: sync.status == SyncStatus.syncing ? null : sync.connect,
            icon: const Icon(Icons.login),
            label: Text(it ? 'Accedi con Google' : 'Mit Google anmelden'),
          ),
          if (sync.status == SyncStatus.syncing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(it ? 'Completa l\'accesso nel browser…' : 'Schließe die Anmeldung im Browser ab…'),
            ),
          if (sync.error != null && sync.status == SyncStatus.error)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('⚠️ ${sync.error}', style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          it ? 'Puoi farlo anche più tardi in Impostazioni > Sincronizzazione.' : 'Das geht auch später unter Einstellungen > Sync & Backup.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _gemini(BuildContext context, AppState app) {
    final it = app.italianUi;
    final theme = Theme.of(context);
    return _pageLayout(
      icon: Icons.auto_awesome,
      title: it ? 'Spiegazioni con l\'IA (facoltativo)' : 'KI-Erklärungen (optional)',
      children: [
        Text(it
            ? 'Con una chiave API Gemini gratuita puoi chattare con l\'IA direttamente nell\'app su ogni domanda – figura compresa. La chiave è tua, resta solo su questo dispositivo e non costa nulla nel piano gratuito.'
            : 'Mit einem kostenlosen Gemini-API-Schlüssel kannst du zu jeder Frage direkt in der App mit der KI chatten – inklusive Bild. Der Schlüssel gehört dir, bleibt nur auf diesem Gerät und ist im Gratis-Kontingent kostenlos.'),
        const SizedBox(height: 12),
        Text(
          it
              ? 'Così si ottiene: 1. apri Google AI Studio, 2. accedi con Google, 3. „Create API key“, 4. copia la chiave qui.'
              : 'So geht\'s: 1. Google AI Studio öffnen, 2. mit Google anmelden, 3. „Create API key“, 4. Schlüssel hier einfügen.',
          style: theme.textTheme.bodySmall,
        ),
        TextButton.icon(
          onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Google AI Studio'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          decoration: InputDecoration(
            labelText: it ? 'Chiave API Gemini' : 'Gemini-API-Schlüssel',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _keyStatus = null),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              onPressed: _testing || _key.text.trim().isEmpty ? null : _testKey,
              child: _testing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(it ? 'Prova' : 'Testen'),
            ),
            const SizedBox(width: 12),
            if (_keyStatus != null) Expanded(child: Text(_keyStatus!)),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          it
              ? 'Senza chiave puoi comunque usare „Chiedi all\'IA“: apre ChatGPT o Claude con la domanda già inserita.'
              : 'Auch ohne Schlüssel kannst du „KI fragen“ nutzen: Das öffnet ChatGPT oder Claude mit der Frage schon eingefügt.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
