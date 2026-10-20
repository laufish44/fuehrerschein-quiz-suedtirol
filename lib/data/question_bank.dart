import 'dart:convert';

import 'package:flutter/services.dart';

class Chapter {
  final int id;
  final String de;
  final String it;
  final List<QuestionGroup> groups = [];
  final List<Question> questions = [];

  Chapter(this.id, this.de, this.it);

  String name(bool italian) => italian ? it : de;
}

class QuestionGroup {
  final int id;
  final Chapter chapter;
  final List<String> images;
  final List<Question> questions = [];

  QuestionGroup(this.id, this.chapter, this.images);

  String? get image => images.isEmpty ? null : images.first;
}

class Question {
  final int id;
  final QuestionGroup group;
  final bool answer;
  final String de;
  final String it;
  final String? image;

  Question(this.id, this.group, this.answer, this.de, this.it, this.image);

  Chapter get chapter => group.chapter;
  String text(bool italian) => italian ? it : de;
  String? get imageAsset => image == null ? null : 'assets/img/$image.webp';

  /// Text in Kleinbuchstaben für die Suche.
  late final String searchText = '${de.toLowerCase()} ${it.toLowerCase()} $id';
}

/// Alle Fragen der Ministeriumsliste (A/B), geladen aus assets/data/questions.json.
class QuestionBank {
  final List<Chapter> chapters;
  final List<QuestionGroup> groups;
  final List<Question> questions;
  final Map<int, Question> byId;
  final Map<int, QuestionGroup> groupById;
  final String source;

  /// Offline-Erklärungen: Fragen-ID bzw. Gruppen-ID -> Text, je Sprache.
  final Map<String, Map<int, String>> questionExplanations;
  final Map<String, Map<int, String>> groupExplanations;

  QuestionBank._(
    this.chapters,
    this.groups,
    this.questions,
    this.source,
    this.questionExplanations,
    this.groupExplanations,
  )   : byId = {for (final q in questions) q.id: q},
        groupById = {for (final g in groups) g.id: g};

  static Future<QuestionBank> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/data/questions.json')) as Map<String, dynamic>;
    final chapters = <Chapter>[
      for (final c in raw['chapters'] as List) Chapter(c['id'] as int, c['de'] as String, c['it'] as String),
    ];
    final chapterById = {for (final c in chapters) c.id: c};
    final groups = <QuestionGroup>[];
    final groupById = <int, QuestionGroup>{};
    for (final g in raw['groups'] as List) {
      final chapter = chapterById[g['ch'] as int]!;
      final group = QuestionGroup(g['id'] as int, chapter, [for (final i in (g['img'] as List?) ?? const []) i as String]);
      groups.add(group);
      groupById[group.id] = group;
      chapter.groups.add(group);
    }
    final questions = <Question>[];
    for (final q in raw['questions'] as List) {
      final group = groupById[q['g'] as int]!;
      final question = Question(
        q['id'] as int,
        group,
        q['a'] as bool,
        q['de'] as String,
        (q['it'] as String?) ?? q['de'] as String,
        q['img'] as String?,
      );
      questions.add(question);
      group.questions.add(question);
      group.chapter.questions.add(question);
    }

    final qExp = <String, Map<int, String>>{};
    final gExp = <String, Map<int, String>>{};
    for (final lang in const ['de', 'it']) {
      try {
        final e = jsonDecode(await rootBundle.loadString('assets/data/explanations_$lang.json')) as Map<String, dynamic>;
        qExp[lang] = {
          for (final entry in ((e['questions'] as Map?) ?? const {}).entries) int.parse(entry.key as String): entry.value as String,
        };
        gExp[lang] = {
          for (final entry in ((e['groups'] as Map?) ?? const {}).entries) int.parse(entry.key as String): entry.value as String,
        };
      } catch (_) {
        qExp[lang] = {};
        gExp[lang] = {};
      }
    }

    return QuestionBank._(chapters, groups, questions, raw['source'] as String? ?? '', qExp, gExp);
  }

  Chapter chapter(int id) => chapters[id - 1];

  /// Erklärung zu einer Frage; fällt auf die andere Sprache zurück.
  ({String? question, String? group, bool otherLanguage}) explanation(Question q, bool italian) {
    final primary = italian ? 'it' : 'de';
    final secondary = italian ? 'de' : 'it';
    final pq = questionExplanations[primary]?[q.id];
    final pg = groupExplanations[primary]?[q.group.id];
    if (pq != null || pg != null) return (question: pq, group: pg, otherLanguage: false);
    final sq = questionExplanations[secondary]?[q.id];
    final sg = groupExplanations[secondary]?[q.group.id];
    return (question: sq, group: sg, otherLanguage: sq != null || sg != null);
  }

  int get explainedCount => questionExplanations['de']?.length ?? 0;

  /// Alle Bilder (Verkehrszeichen/Situationen) mit ihren Fragen, für das Lexikon.
  List<({String image, List<Question> questions})> imageEntries() {
    final map = <String, List<Question>>{};
    for (final q in questions) {
      if (q.image != null) (map[q.image!] ??= []).add(q);
    }
    final entries = [for (final e in map.entries) (image: e.key, questions: e.value)];
    entries.sort((a, b) {
      final c = a.questions.first.chapter.id.compareTo(b.questions.first.chapter.id);
      return c != 0 ? c : a.questions.first.group.id.compareTo(b.questions.first.group.id);
    });
    return entries;
  }
}
