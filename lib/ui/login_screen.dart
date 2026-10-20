import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/drive_sync.dart';
import 'widgets.dart';

/// Pflicht-Anmeldung mit dem eigenen Google-Konto. Der Lernstand liegt im
/// versteckten App-Ordner des eigenen Google Drive.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sync = context.watch<DriveSync>();
    final it = app.italianUi;
    final theme = Theme.of(context);
    final busy = sync.status == SyncStatus.syncing;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'de', label: Text('DE')),
                        ButtonSegment(value: 'it', label: Text('IT')),
                      ],
                      selected: {app.settings.uiLanguage},
                      onSelectionChanged: (v) => app.updateSettings((s) {
                        s.uiLanguage = v.first;
                        s.questionLanguage = v.first;
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(child: Image.asset('assets/icon/icon.png', width: 96, height: 96)),
                  const SizedBox(height: 16),
                  Text(
                    it ? 'Quiz Patente Alto Adige' : 'Führerschein Quiz Südtirol',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    it
                        ? 'Per usare l\'app accedi con il tuo account Google. I tuoi progressi vengono salvati in una cartella nascosta del TUO Google Drive: non perdi nulla e continui su telefono e PC.'
                        : 'Um die App zu nutzen, melde dich mit deinem Google-Konto an. Dein Lernstand wird in einem versteckten Ordner in DEINEM Google Drive gespeichert – so geht nichts verloren und du lernst auf Handy und PC weiter.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  _Point(
                    icon: Icons.lock_outline,
                    text: it
                        ? 'L\'app vede solo il proprio file di salvataggio, non il resto del tuo Drive.'
                        : 'Die App sieht nur ihre eigene Sicherungsdatei, nicht den Rest deines Drives.',
                  ),
                  _Point(
                    icon: Icons.person_outline,
                    text: it
                        ? 'Il tuo accesso resta solo su questo dispositivo – nessun altro ha accesso ai tuoi dati.'
                        : 'Deine Anmeldung bleibt nur auf diesem Gerät – niemand sonst hat Zugriff auf deine Daten.',
                  ),
                  _Point(
                    icon: Icons.wifi_off_outlined,
                    text: it
                        ? 'Dopo l\'accesso l\'app funziona anche offline.'
                        : 'Nach der Anmeldung funktioniert die App auch offline.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: busy ? null : sync.connect,
                    icon: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: Text(it ? 'Accedi con Google' : 'Mit Google anmelden'),
                  ),
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        it
                            ? 'Si è aperto il browser: scegli il tuo account e consenti l\'accesso, poi torna qui.'
                            : 'Der Browser hat sich geöffnet: Konto wählen, Zugriff erlauben und dann hierher zurückkehren.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (sync.status == SyncStatus.error && sync.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '⚠️ ${sync.error!.replaceFirst('Exception: ', '')}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    it
                        ? 'Non hai un account Google? Puoi crearne uno gratis durante l\'accesso.'
                        : 'Noch kein Google-Konto? Du kannst während der Anmeldung kostenlos eines erstellen.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: correctColor),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
