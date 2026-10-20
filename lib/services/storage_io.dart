import 'dart:io';

import 'package:path_provider/path_provider.dart';

Directory? _dir;

Future<Directory> _base() async {
  if (_dir != null) return _dir!;
  final d = await getApplicationSupportDirectory();
  await d.create(recursive: true);
  return _dir = d;
}

Future<String?> readFile(String name) async {
  final f = File('${(await _base()).path}${Platform.pathSeparator}$name');
  if (await f.exists()) return f.readAsString();
  // Falls beim letzten Speichern etwas schiefging: Sicherungskopie nehmen.
  final bak = File('${f.path}.bak');
  if (await bak.exists()) return bak.readAsString();
  return null;
}

Future<void> writeFile(String name, String data) async {
  final path = '${(await _base()).path}${Platform.pathSeparator}$name';
  final tmp = File('$path.tmp');
  await tmp.writeAsString(data, flush: true);
  final f = File(path);
  if (await f.exists()) {
    await f.copy('$path.bak');
  }
  await tmp.rename(path);
}

Future<String> location() async => (await _base()).path;
