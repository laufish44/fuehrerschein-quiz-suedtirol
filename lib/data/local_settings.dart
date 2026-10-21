import 'user_data.dart';

/// Einstellungen, die nur auf diesem Gerät gelten (werden nicht synchronisiert).
class LocalSettings {
  String deviceId;
  String themeMode; // system | light | dark
  bool reminderEnabled;
  int reminderHour;
  int reminderMinute;
  bool autoUpdate;
  double ttsRate;
  bool ttsAutoRead;
  String geminiKey;
  String geminiModel;
  String driveRefreshToken;
  int lastSyncTs;
  String lastSyncError;
  bool onboardingDone;
  bool keyboardHints;

  /// Wurde schon einmal zur Einrichtung von Google Drive bzw. Gemini aufgefordert?
  bool drivePrompted;
  bool geminiPrompted;

  /// Abzeichen, die schon angezeigt wurden (für den „Neu“-Hinweis).
  List<String> seenAchievements;

  LocalSettings({
    String? deviceId,
    this.themeMode = 'system',
    this.reminderEnabled = false,
    this.reminderHour = 18,
    this.reminderMinute = 0,
    this.autoUpdate = true,
    this.ttsRate = 0.5,
    this.ttsAutoRead = false,
    this.geminiKey = '',
    this.geminiModel = '',
    this.driveRefreshToken = '',
    this.lastSyncTs = 0,
    this.lastSyncError = '',
    this.onboardingDone = false,
    this.keyboardHints = true,
    this.drivePrompted = false,
    this.geminiPrompted = false,
    List<String>? seenAchievements,
  })  : deviceId = deviceId ?? randomId(),
        seenAchievements = seenAchievements ?? [];

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'themeMode': themeMode,
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'autoUpdate': autoUpdate,
        'ttsRate': ttsRate,
        'ttsAutoRead': ttsAutoRead,
        'geminiKey': geminiKey,
        'geminiModel': geminiModel,
        'driveRefreshToken': driveRefreshToken,
        'lastSyncTs': lastSyncTs,
        'lastSyncError': lastSyncError,
        'onboardingDone': onboardingDone,
        'keyboardHints': keyboardHints,
        'drivePrompted': drivePrompted,
        'geminiPrompted': geminiPrompted,
        'seenAchievements': seenAchievements,
      };

  factory LocalSettings.fromJson(Map<String, dynamic> j) {
    final d = LocalSettings(deviceId: j['deviceId'] as String?);
    return d
      ..themeMode = j['themeMode'] as String? ?? d.themeMode
      ..reminderEnabled = j['reminderEnabled'] as bool? ?? d.reminderEnabled
      ..reminderHour = j['reminderHour'] as int? ?? d.reminderHour
      ..reminderMinute = j['reminderMinute'] as int? ?? d.reminderMinute
      ..autoUpdate = j['autoUpdate'] as bool? ?? d.autoUpdate
      ..ttsRate = (j['ttsRate'] as num?)?.toDouble() ?? d.ttsRate
      ..ttsAutoRead = j['ttsAutoRead'] as bool? ?? d.ttsAutoRead
      ..geminiKey = j['geminiKey'] as String? ?? d.geminiKey
      ..geminiModel = j['geminiModel'] as String? ?? d.geminiModel
      ..driveRefreshToken = j['driveRefreshToken'] as String? ?? d.driveRefreshToken
      ..lastSyncTs = j['lastSyncTs'] as int? ?? d.lastSyncTs
      ..lastSyncError = j['lastSyncError'] as String? ?? d.lastSyncError
      ..onboardingDone = j['onboardingDone'] as bool? ?? d.onboardingDone
      ..keyboardHints = j['keyboardHints'] as bool? ?? d.keyboardHints
      ..drivePrompted = j['drivePrompted'] as bool? ?? d.drivePrompted
      ..geminiPrompted = j['geminiPrompted'] as bool? ?? d.geminiPrompted
      ..seenAchievements = [for (final s in (j['seenAchievements'] as List?) ?? const []) s as String];
  }
}
