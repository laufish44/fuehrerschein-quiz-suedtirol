// Baut assets/data/explanations_<sprache>.json aus den Textdateien in explanations/<sprache>/.
//
//   dart run tools/build_explanations.dart [de|it]
//
// Format der Textdateien (eine Zeile pro Eintrag, Leerzeilen und #-Kommentare werden ignoriert):
//   G 4328: Erklärung zur ganzen Gruppe (Bild/Thema)
//   21810: Erklärung zu einer einzelnen Aussage
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final lang = args.isEmpty ? 'de' : args.first;
  final data = jsonDecode(File('assets/data/questions.json').readAsStringSync()) as Map<String, dynamic>;
  final questionIds = {for (final q in data['questions'] as List) q['id'] as int};
  final groupIds = {for (final g in data['groups'] as List) g['id'] as int};
  final groupCh = {for (final g in data['groups'] as List) g['id'] as int: g['ch'] as int};
  final qGroup = {for (final q in data['questions'] as List) q['id'] as int: q['g'] as int};

  final groups = <String, String>{};
  final questions = <String, String>{};
  final errors = <String>[];
  final dir = Directory('explanations/$lang');
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  final line = RegExp(r'^(G\s+)?(\d+):\s*(.+)$');
  for (final f in files) {
    var n = 0;
    for (final raw in f.readAsLinesSync()) {
      n++;
      final l = raw.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      final m = line.firstMatch(l);
      if (m == null) {
        errors.add('${f.path}:$n: unbekanntes Format');
        continue;
      }
      final id = int.parse(m.group(2)!);
      final text = m.group(3)!.trim();
      if (m.group(1) != null) {
        if (!groupIds.contains(id)) errors.add('${f.path}:$n: Gruppe $id gibt es nicht');
        groups['$id'] = text;
      } else {
        if (!questionIds.contains(id)) errors.add('${f.path}:$n: Frage $id gibt es nicht');
        questions['$id'] = text;
      }
    }
  }

  File('assets/data/explanations_$lang.json')
      .writeAsStringSync(jsonEncode({'groups': groups, 'questions': questions}));

  // Abdeckung je Kapitel
  final perCh = <int, List<int>>{};
  for (final q in questionIds) {
    final c = groupCh[qGroup[q]]!;
    final l = perCh[c] ??= [0, 0];
    l[1]++;
    if (questions.containsKey('$q')) l[0]++;
  }
  stdout.writeln('Sprache $lang: ${questions.length}/${questionIds.length} Aussagen, ${groups.length}/${groupIds.length} Gruppen');
  for (final c in perCh.keys.toList()..sort()) {
    final l = perCh[c]!;
    if (l[0] > 0) stdout.writeln('  Kapitel ${c.toString().padLeft(2)}: ${l[0]}/${l[1]}');
  }
  for (final e in errors) {
    stderr.writeln('FEHLER $e');
  }
  if (errors.isNotEmpty) exit(1);
}
