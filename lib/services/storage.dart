import 'storage_web.dart' if (dart.library.io) 'storage_io.dart' as impl;

/// Liest/schreibt kleine Text-Dateien (JSON) im App-Datenordner bzw. im Browser-Speicher.
class Storage {
  static Future<String?> read(String name) => impl.readFile(name);
  static Future<void> write(String name, String data) => impl.writeFile(name, data);
  static Future<String> location() => impl.location();
}
