import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'data/user_data.dart';
import 'services/drive_sync.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'ui/exam_tab.dart';
import 'ui/home_tab.dart';
import 'ui/learn_tab.dart';
import 'ui/more_tab.dart';
import 'ui/question_list_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/stats_tab.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await AppState.load();
  final updates = UpdateService();
  await updates.init();
  final sync = DriveSync(app);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: updates),
      ChangeNotifierProvider.value(value: sync),
    ],
    child: const QuizApp(),
  ));
}

const _seed = Color(0xFF2563EB);

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      elevation: 0,
      color: b == Brightness.light ? scheme.surfaceContainerLow : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: appTitle(app.italianUi),
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: switch (app.local.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: Locale(app.settings.uiLanguage),
      supportedLocales: const [Locale('de'), Locale('it')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  bool _waitingToInstall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    final sync = context.read<DriveSync>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      app.save();
      if (state == AppLifecycleState.paused) sync.syncNow();
    } else if (state == AppLifecycleState.resumed) {
      final last = sync.lastSync;
      if (last == null || DateTime.now().difference(last).inMinutes >= 10) sync.syncNow();
    }
  }

  Future<void> _startup() async {
    final app = context.read<AppState>();
    final sync = context.read<DriveSync>();
    final updates = context.read<UpdateService>();

    if (!app.local.onboardingDone) await _onboarding();

    unawaited(sync.syncNow());

    if (NotificationService.supported) {
      await NotificationService.init();
      if (app.local.reminderEnabled) {
        await NotificationService.schedule(
          enabled: true,
          hour: app.local.reminderHour,
          minute: app.local.reminderMinute,
          italian: app.italianUi,
          examDate: app.settings.examDate,
        );
      }
    }

    if (updates.supported && app.local.autoUpdate) {
      await Future.delayed(const Duration(seconds: 3));
      if (await updates.check() && await updates.download()) {
        _installWhenIdle();
      }
    }
  }

  /// Installiert ein fertig geladenes Update, sobald keine Übung/Prüfung läuft.
  void _installWhenIdle() {
    final app = context.read<AppState>();
    final updates = context.read<UpdateService>();
    if (!app.sessionActive) {
      _install(updates);
      return;
    }
    if (_waitingToInstall) return;
    _waitingToInstall = true;
    void listener() {
      if (!app.sessionActive) {
        app.removeListener(listener);
        _waitingToInstall = false;
        _install(updates);
      }
    }

    app.addListener(listener);
  }

  Future<void> _install(UpdateService updates) async {
    final app = context.read<AppState>();
    await app.save();
    if (!mounted) return;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(app.italianUi
            ? 'Installazione della versione ${updates.release?.version}… l\'app si riavvia.'
            : 'Version ${updates.release?.version} wird installiert … die App startet neu.'),
      ));
      await Future.delayed(const Duration(seconds: 2));
    }
    await updates.install();
  }

  Future<void> _onboarding() async {
    final app = context.read<AppState>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _OnboardingDialog(),
    );
    app.updateLocal((l) => l.onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = isWide(context);
    final destinations = [
      (Icons.home_outlined, Icons.home, context.tr('Start', 'Home')),
      (Icons.menu_book_outlined, Icons.menu_book, context.tr('Lernen', 'Studio')),
      (Icons.assignment_outlined, Icons.assignment, context.tr('Prüfung', 'Esame')),
      (Icons.insights_outlined, Icons.insights, context.tr('Statistik', 'Statistiche')),
      (Icons.more_horiz, Icons.more_horiz, context.tr('Mehr', 'Altro')),
    ];
    const pages = [HomeTab(), LearnTab(), ExamTab(), StatsTab(), MoreTab()];

    final body = IndexedStack(index: _tab, children: pages);

    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0
            ? (wide ? appTitle(app.italianUi) : (app.italianUi ? 'Quiz Patente' : 'Führerschein Quiz'))
            : destinations[_tab].$3),
        actions: [
          IconButton(
            tooltip: context.tr('Suche', 'Cerca'),
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            tooltip: context.tr('Einstellungen', 'Impostazioni'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Image.asset('assets/icon/icon.png', width: 40, height: 40),
                  ),
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final d in destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
    );
  }
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  DateTime? _examDate;
  int _goal = 60;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final it = app.italianUi;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Image.asset('assets/icon/icon.png', width: 36, height: 36),
          const SizedBox(width: 12),
          Expanded(child: Text(it ? 'Benvenuto!' : 'Willkommen!')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it
                  ? 'Qui trovi tutte le 7.020 domande ufficiali per la patente A/B – in tedesco e italiano.'
                  : 'Hier findest du alle 7.020 offiziellen Prüfungsfragen für den Führerschein A/B – auf Deutsch und Italienisch.'),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
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
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            app.updateSettings((s) {
              s.dailyGoal = _goal;
              if (_examDate != null) s.examDate = dayKey(_examDate!);
            });
            Navigator.pop(context);
          },
          child: Text(it ? 'Iniziamo!' : 'Los geht\'s!'),
        ),
      ],
    );
  }
}
