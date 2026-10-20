/// Zentrale Konfiguration der App.
class AppConfig {
  static const appName = 'Führerschein Quiz Südtirol';

  /// GitHub-Repository, aus dem Updates geladen werden.
  static const githubOwner = 'laufish44';
  static const githubRepo = 'fuehrerschein-quiz-suedtirol';
  static const githubUrl = 'https://github.com/$githubOwner/$githubRepo';
  static const latestReleaseApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Google-OAuth-Client vom Typ "Desktop-App" für den Google-Drive-Sync.
  /// Bei Desktop-Clients gilt das Secret laut Google nicht als geheim und darf
  /// in der App stehen. Leer = Sync noch nicht eingerichtet.
  static const googleClientId = '';
  static const googleClientSecret = '';
  static const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const driveFileName = 'fuehrerschein-quiz-sync.json';

  static bool get driveConfigured => googleClientId.isNotEmpty;

  /// Standard-Modell für den optionalen Gemini-Chat mit eigenem Key.
  static const defaultGeminiModel = 'gemini-flash-latest';

  /// Offizielle Prüfung (seit 20.12.2021): 30 Fragen, 20 Minuten, max. 3 Fehler.
  static const examQuestions = 30;
  static const examMinutes = 20;
  static const examMaxErrors = 3;
}
