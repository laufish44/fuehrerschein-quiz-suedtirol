// Gibt alle Fragengruppen eines Kapitels kompakt aus – als Vorlage zum Schreiben der Erklärungen.
//
//   dart run tools/dump_chapter.dart <kapitel> [it]
//
// Ausgabe je Gruppe:  G <gruppe> [bild] … dann je Aussage:  <id> R|F <text>
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final chapter = int.parse(args.first);
  final italian = args.length > 1 && args[1] == 'it';
  final data = jsonDecode(File('assets/data/questions.json').readAsStringSync()) as Map<String, dynamic>;
  final ch = (data['chapters'] as List).firstWhere((c) => c['id'] == chapter);
  stdout.writeln('# Kapitel $chapter: ${ch['de']} / ${ch['it']}');
  final groups = {for (final g in data['groups'] as List) g['id']: g};
  final byGroup = <int, List<Map<String, dynamic>>>{};
  for (final q in (data['questions'] as List).cast<Map<String, dynamic>>()) {
    if (groups[q['g']]['ch'] == chapter) (byGroup[q['g'] as int] ??= []).add(q);
  }
  for (final entry in byGroup.entries) {
    final g = groups[entry.key];
    final imgs = (g['img'] as List?)?.join(',') ?? '-';
    stdout.writeln('\nG ${entry.key} [$imgs]');
    for (final q in entry.value) {
      final img = q['img'] != null && (g['img'] as List).length > 1 ? ' {${q['img']}}' : '';
      stdout.writeln('${q['id']} ${q['a'] == true ? 'R' : 'F'}$img ${italian ? q['it'] : q['de']}');
    }
  }
}
