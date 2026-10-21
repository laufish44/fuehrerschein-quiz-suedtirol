/// Zentrale Konfiguration der App.
class AppConfig {
  static const appName = 'Führerschein Quiz Südtirol';

  /// GitHub-Repository, aus dem Updates geladen werden.
  static const githubOwner = 'laufish44';
  static const githubRepo = 'fuehrerschein-quiz-suedtirol';
  static const githubUrl = 'https://github.com/$githubOwner/$githubRepo';
  static const latestReleaseApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Kennung der App bei Google (OAuth-Client vom Typ "Desktop-App") für den Drive-Sync.
  /// Das ist KEIN Zugang zu einem Drive – jeder Nutzer meldet sich mit seinem eigenen Konto an,
  /// und sein Token bleibt nur auf seinem Gerät. Die Werte stehen nicht im Quellcode, sondern
  /// werden beim Bauen über GitHub-Secrets gesetzt:
  ///   flutter build ... --dart-define=GOOGLE_CLIENT_ID=... --dart-define=GOOGLE_CLIENT_SECRET=...
  /// Leer = Sync nicht eingerichtet (z. B. lokale Entwicklungs-Builds).
  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const googleClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
  static const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const driveFileName = 'fuehrerschein-quiz-sync.json';

  static bool get driveConfigured => googleClientId.isNotEmpty;

  /// Standard-Modell für den optionalen Gemini-Chat mit eigenem Key.
  /// Das kleine Modell antwortet in 1–2 s; das große (gemini-flash-latest) brauchte im
  /// Oktober 2026 wegen Überlastung oft über 2 Minuten.
  static const defaultGeminiModel = 'gemini-flash-lite-latest';

  /// Offizielle Prüfung (seit 20.12.2021): 30 Fragen, 20 Minuten, max. 3 Fehler.
  static const examQuestions = 30;
  static const examMinutes = 20;
  static const examMaxErrors = 3;
}
