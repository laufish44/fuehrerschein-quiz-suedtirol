import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import 'update_web.dart' if (dart.library.io) 'update_io.dart' as platform;

enum UpdateStatus { idle, checking, upToDate, available, downloading, ready, installing, error }

class ReleaseInfo {
  final String version;
  final String notes;
  final String htmlUrl;
  final String? assetUrl;
  final String? assetName;
  final int assetSize;
  final String? sha256;

  ReleaseInfo({
    required this.version,
    required this.notes,
    required this.htmlUrl,
    this.assetUrl,
    this.assetName,
    this.assetSize = 0,
    this.sha256,
  });
}

/// Vergleicht Versionen wie "1.2.10" > "1.2.9".
int compareVersions(String a, String b) {
  List<int> parse(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parse(a), pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Prüft GitHub-Releases auf neue Versionen, lädt sie herunter und installiert sie.
/// Windows: Installer läuft still im Hintergrund und startet die App neu.
/// Android: Das System zeigt den Installationsdialog (ein Tipp nötig).
class UpdateService extends ChangeNotifier {
  UpdateStatus status = UpdateStatus.idle;
  ReleaseInfo? release;
  double progress = 0;
  String? error;
  String currentVersion = '';
  String? _downloadedPath;

  bool get supported => platform.updatesSupported;

  Future<void> init() async {
    try {
      currentVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      currentVersion = '?';
    }
    notifyListeners();
  }

  void _set(UpdateStatus s, {String? err}) {
    status = s;
    error = err;
    notifyListeners();
  }

  Future<bool> check() async {
    if (status == UpdateStatus.downloading || status == UpdateStatus.installing) return false;
    _set(UpdateStatus.checking);
    try {
      final res = await http.get(Uri.parse(AppConfig.latestReleaseApi), headers: {
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) {
        _set(UpdateStatus.upToDate);
        return false;
      }
      if (res.statusCode != 200) throw Exception('GitHub: HTTP ${res.statusCode}');
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final version = (j['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
      Map<String, dynamic>? asset;
      for (final a in (j['assets'] as List).cast<Map<String, dynamic>>()) {
        final name = (a['name'] as String).toLowerCase();
        if (platform.assetMatches(name)) {
          asset = a;
          break;
        }
      }
      final digest = asset?['digest'] as String?;
      release = ReleaseInfo(
        version: version,
        notes: (j['body'] as String?) ?? '',
        htmlUrl: j['html_url'] as String,
        assetUrl: asset?['browser_download_url'] as String?,
        assetName: asset?['name'] as String?,
        assetSize: (asset?['size'] as int?) ?? 0,
        sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7) : null,
      );
      final newer = compareVersions(version, currentVersion) > 0;
      _set(newer ? UpdateStatus.available : UpdateStatus.upToDate);
      return newer;
    } catch (e) {
      _set(UpdateStatus.error, err: e.toString());
      return false;
    }
  }

  Future<bool> download() async {
    final r = release;
    if (r == null || r.assetUrl == null || !supported) return false;
    _set(UpdateStatus.downloading);
    progress = 0;
    try {
      _downloadedPath = await platform.downloadUpdate(
        url: r.assetUrl!,
        fileName: r.assetName ?? 'update',
        expectedSize: r.assetSize,
        expectedSha256: r.sha256,
        onProgress: (p) {
          progress = p;
          notifyListeners();
        },
      );
      _set(UpdateStatus.ready);
      return true;
    } catch (e) {
      _set(UpdateStatus.error, err: e.toString());
      return false;
    }
  }

  /// Installiert das heruntergeladene Update. Unter Windows beendet sich die App dabei.
  Future<void> install() async {
    final path = _downloadedPath;
    if (path == null) return;
    _set(UpdateStatus.installing);
    try {
      await platform.installUpdate(path);
      // Android: Installationsdialog ist offen; falls abgebrochen, bleibt das Update bereit.
      _set(UpdateStatus.ready);
    } catch (e) {
      _set(UpdateStatus.error, err: e.toString());
    }
  }
}
