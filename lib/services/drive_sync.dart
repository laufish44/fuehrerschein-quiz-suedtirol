import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';
import '../config.dart';
import '../data/user_data.dart';
import 'oauth_web.dart' if (dart.library.io) 'oauth_io.dart' as oauth;

enum SyncStatus { off, idle, syncing, ok, error }

/// Synchronisiert den Lernstand über eine JSON-Datei im versteckten App-Ordner
/// des eigenen Google Drive (Bereich drive.appdata: die App sieht nur ihre eigene Datei).
class DriveSync extends ChangeNotifier {
  final AppState app;
  SyncStatus status = SyncStatus.off;
  String? error;
  Timer? _debounce;
  String? _accessToken;
  DateTime? _tokenExpiry;

  /// Laufender Abgleich (null = keiner).
  Future<void>? _current;

  /// Während eines Abgleichs kam ein neuer Anlass dazu → danach noch einmal abgleichen.
  bool _pending = false;

  DriveSync(this.app) {
    status = connected ? SyncStatus.idle : SyncStatus.off;
    app.onDataChanged = scheduleSync;
  }

  static bool get supported => oauth.loopbackSupported && AppConfig.driveConfigured;
  bool get connected => app.local.driveRefreshToken.isNotEmpty;
  DateTime? get lastSync =>
      app.local.lastSyncTs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(app.local.lastSyncTs * 1000);

  void _set(SyncStatus s, [String? err]) {
    status = s;
    error = err;
    notifyListeners();
  }

  /// Anmeldung im Browser (Google-Konto wählen, Zugriff erlauben).
  Future<void> connect() async {
    _set(SyncStatus.syncing);
    try {
      final tokens = await oauth.signInWithLoopback(
        clientId: AppConfig.googleClientId,
        clientSecret: AppConfig.googleClientSecret,
        scope: AppConfig.driveScope,
      );
      _accessToken = tokens.accessToken;
      _tokenExpiry = DateTime.now().add(Duration(seconds: tokens.expiresIn - 60));
      app.updateLocal((l) => l.driveRefreshToken = tokens.refreshToken);
      await syncNow();
    } catch (e) {
      _set(SyncStatus.error, e.toString());
    }
  }

  Future<void> disconnect() async {
    final token = app.local.driveRefreshToken;
    app.updateLocal((l) {
      l.driveRefreshToken = '';
      l.lastSyncTs = 0;
    });
    _accessToken = null;
    _set(SyncStatus.off);
    try {
      await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': token});
    } catch (_) {}
  }

  void scheduleSync() {
    if (!connected || !supported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), syncNow);
  }

  Future<String> _token() async {
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken!;
    }
    final res = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': AppConfig.googleClientId,
      'client_secret': AppConfig.googleClientSecret,
      'refresh_token': app.local.driveRefreshToken,
      'grant_type': 'refresh_token',
    });
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      if (j['error'] == 'invalid_grant') {
        // Zugriff wurde widerrufen oder ist abgelaufen: neu verbinden nötig.
        app.updateLocal((l) => l.driveRefreshToken = '');
        throw Exception('Google-Anmeldung abgelaufen. Bitte neu verbinden.');
      }
      throw Exception('Token: ${j['error_description'] ?? j['error'] ?? res.statusCode}');
    }
    _accessToken = j['access_token'] as String;
    _tokenExpiry = DateTime.now().add(Duration(seconds: (j['expires_in'] as int? ?? 3600) - 60));
    return _accessToken!;
  }

  /// Gleicht sofort ab. Läuft schon ein Abgleich, wird danach noch einmal abgeglichen,
  /// damit nichts verloren geht, was währenddessen dazukam. Das Future endet erst,
  /// wenn alles hochgeladen ist (oder ein Fehler auftrat).
  Future<void> syncNow() {
    _debounce?.cancel();
    if (!connected || !supported) return Future.value();
    if (_current != null) {
      _pending = true;
      return _current!;
    }
    return _current = _syncLoop();
  }

  Future<void> _syncLoop() async {
    try {
      bool ok;
      do {
        _pending = false;
        ok = await _syncOnce();
      } while (ok && _pending && connected);
    } finally {
      _current = null;
    }
  }

  /// Beim Beenden der App: offene Änderungen noch hochladen (höchstens [timeout] lang).
  Future<void> flush({Duration timeout = const Duration(seconds: 8)}) async {
    if (!connected || !supported) return;
    try {
      await syncNow().timeout(timeout);
    } catch (_) {}
  }

  Future<bool> _syncOnce() async {
    _set(SyncStatus.syncing);
    try {
      final token = await _token();
      final headers = {'Authorization': 'Bearer $token'};
      final q = Uri.encodeQueryComponent("name='${AppConfig.driveFileName}'");
      final list = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,modifiedTime)'),
        headers: headers,
      );
      if (list.statusCode != 200) throw Exception('Drive: HTTP ${list.statusCode} ${list.body}');
      final files = (jsonDecode(list.body)['files'] as List).cast<Map<String, dynamic>>();
      String? fileId = files.isEmpty ? null : files.first['id'] as String;

      var needsUpload = fileId == null;
      if (fileId != null) {
        final dl = await http.get(
          Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
          headers: headers,
        );
        if (dl.statusCode != 200) throw Exception('Drive-Download: HTTP ${dl.statusCode}');
        final remote = UserData.fromJson(jsonDecode(utf8.decode(dl.bodyBytes)) as Map<String, dynamic>);
        app.mergeRemote(remote);
        // Hat der Drive-Stand etwas nicht, was lokal vorhanden ist?
        needsUpload = remote.mergeFrom(app.data);
      }

      if (needsUpload) {
        final body = utf8.encode(jsonEncode(app.data.toJson()));
        if (fileId == null) {
          const boundary = 'fqs_boundary_7f3a';
          final meta = jsonEncode({
            'name': AppConfig.driveFileName,
            'parents': ['appDataFolder'],
          });
          final multipart = <int>[
            ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'),
            ...utf8.encode('--$boundary\r\nContent-Type: application/json\r\n\r\n'),
            ...body,
            ...utf8.encode('\r\n--$boundary--'),
          ];
          final up = await http.post(
            Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
            headers: {...headers, 'Content-Type': 'multipart/related; boundary=$boundary'},
            body: multipart,
          );
          if (up.statusCode != 200) throw Exception('Drive-Upload: HTTP ${up.statusCode} ${up.body}');
        } else {
          final up = await http.patch(
            Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: body,
          );
          if (up.statusCode != 200) throw Exception('Drive-Upload: HTTP ${up.statusCode} ${up.body}');
        }
      }
      app.updateLocal((l) {
        l.lastSyncTs = nowSeconds();
        l.lastSyncError = '';
      });
      _set(SyncStatus.ok);
      return true;
    } catch (e) {
      app.updateLocal((l) => l.lastSyncError = e.toString());
      _set(SyncStatus.error, e.toString());
      return false;
    }
  }
}
