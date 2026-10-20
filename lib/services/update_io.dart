import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('fuehrerschein_quiz/updater');

bool get updatesSupported => Platform.isAndroid || Platform.isWindows;

bool assetMatches(String name) {
  if (Platform.isAndroid) return name.endsWith('.apk');
  if (Platform.isWindows) return name.endsWith('-setup.exe');
  return false;
}

Future<String> downloadUpdate({
  required String url,
  required String fileName,
  required int expectedSize,
  required String? expectedSha256,
  required void Function(double) onProgress,
}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates');
  await dir.create(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');

  // Schon vollständig heruntergeladen?
  if (await file.exists() && expectedSize > 0 && await file.length() == expectedSize) {
    if (expectedSha256 == null || (await sha256.bind(file.openRead()).first).toString() == expectedSha256) {
      onProgress(1);
      return file.path;
    }
  }
  // Alte Downloads aufräumen.
  await for (final f in dir.list()) {
    try {
      await f.delete();
    } catch (_) {}
  }

  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(url)));
    if (res.statusCode != 200) throw Exception('Download fehlgeschlagen (HTTP ${res.statusCode})');
    final total = res.contentLength ?? expectedSize;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
  } finally {
    client.close();
  }

  if (expectedSha256 != null) {
    final hash = (await sha256.bind(file.openRead()).first).toString();
    if (hash != expectedSha256) {
      await file.delete();
      throw Exception('Prüfsumme des Updates stimmt nicht – Download verworfen.');
    }
  }
  return file.path;
}

Future<void> installUpdate(String path) async {
  if (Platform.isWindows) {
    // Der Installer ersetzt die App still und startet sie danach neu.
    await Process.start(
      path,
      ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
  if (Platform.isAndroid) {
    await _channel.invokeMethod('installApk', {'path': path});
  }
}
