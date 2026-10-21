import 'dart:convert';

import 'package:flutter/services.dart';

/// Ein Kapitel – entweder ein Kapitel des Theoriebuchs (wird in der App angezeigt)
/// oder eines der 25 Kapitel des Ministeriumsprogramms (nur intern für die Prüfungszusammenstellung).
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

  /// Kapitel im Theoriebuch (für die Anzeige).
  final Chapter chapter;

  /// Kapitel des Ministeriumsprogramms (für die Prüfungssimulation).
  final Chapter examChapter;
  final List<String> images;
  final List<Question> questions = [];

  QuestionGroup(this.id, this.chapter, this.examChapter, this.images);

  String? get image => images.isEmpty ? null : images.first;
}

class Question {
  final int id;
  final QuestionGroup group;
  final bool answer;
  final String de;
  final String it;
  final String? image;

  /// Wie leicht man diese Aussage mit einer Aussage gegenteiliger Lösung derselben Gruppe
  /// verwechseln kann (0..1). Hoch = "Fallen-Frage".
  double trickiness = 0;

  /// Die ähnlichste Aussage derselben Gruppe mit gegenteiliger Lösung.
  Question? trapPartner;

  Question(this.id, this.group, this.answer, this.de, this.it, this.image);

  Chapter get chapter => group.chapter;
  Chapter get examChapter => group.examChapter;
  String text(bool italian) => italian ? it : de;
  String? get imageAsset => image == null ? null : 'assets/img/$image.webp';

  /// Text in Kleinbuchstaben für die Suche.
  late final String searchText = '${de.toLowerCase()} ${it.toLowerCase()} $id';
}

/// Alle Fragen der Ministeriumsliste (A/B), geladen aus assets/data/questions.json.
class QuestionBank {
  /// Kapitel des Theoriebuchs, die Fragen enthalten (in Buchreihenfolge).
  final List<Chapter> chapters;

  /// Die 25 Kapitel des Ministeriumsprogramms.
  final List<Chapter> examChapters;
  final List<QuestionGroup> groups;
  final List<Question> questions;
  final Map<int, Question> byId;
  final Map<int, QuestionGroup> groupById;
  final Map<int, Chapter> _chapterById;
  final String source;

  /// Offline-Erklärungen: Fragen-ID bzw. Gruppen-ID -> Text, je Sprache.
  final Map<String, Map<int, String>> questionExplanations;
  final Map<String, Map<int, String>> groupExplanations;

  QuestionBank._(
    this.chapters,
    this.examChapters,
    this.groups,
    this.questions,
    this.source,
    this.questionExplanations,
    this.groupExplanations,
  )   : byId = {for (final q in questions) q.id: q},
        groupById = {for (final g in groups) g.id: g},
        _chapterById = {for (final c in chapters) c.id: c};

  static Future<QuestionBank> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/data/questions.json')) as Map<String, dynamic>;
    final book = jsonDecode(await rootBundle.loadString('assets/data/book_chapters.json')) as Map<String, dynamic>;

    final examChapters = <Chapter>[
      for (final c in raw['chapters'] as List) Chapter(c['id'] as int, c['de'] as String, c['it'] as String),
    ];
    final examById = {for (final c in examChapters) c.id: c};
    final bookChapters = <Chapter>[
      for (final c in book['chapters'] as List) Chapter(c['id'] as int, c['de'] as String, c['it'] as String),
    ];
    final bookById = {for (final c in bookChapters) c.id: c};
    final fromExam = {
      for (final e in (book['fromExam'] as Map).entries) int.parse(e.key as String): e.value as int,
    };
    final groupOverride = {
      for (final e in (book['groups'] as Map).entries) int.parse(e.key as String): e.value as int,
    };

    final groups = <QuestionGroup>[];
    final groupById = <int, QuestionGroup>{};
    for (final g in raw['groups'] as List) {
      final id = g['id'] as int;
      final exam = examById[g['ch'] as int]!;
      final chapter = bookById[groupOverride[id] ?? fromExam[exam.id]]!;
      final group = QuestionGroup(id, chapter, exam, [for (final i in (g['img'] as List?) ?? const []) i as String]);
      groups.add(group);
      groupById[id] = group;
      chapter.groups.add(group);
      exam.groups.add(group);
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
      group.examChapter.questions.add(question);
    }
    _computeTrickiness(groups);

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

    return QuestionBank._(
      [for (final c in bookChapters) if (c.questions.isNotEmpty) c],
      examChapters,
      groups,
      questions,
      raw['source'] as String? ?? '',
      qExp,
      gExp,
    );
  }

  /// Buchkapitel nach Nummer.
  Chapter chapter(int id) => _chapterById[id] ?? chapters.first;

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

  /// Fallen-Fragen: Aussagen, die einer Aussage mit gegenteiliger Lösung sehr ähnlich sind.
  late final List<Question> trickyQuestions = () {
    final list = questions.where((q) => q.trickiness >= 0.55).toList()
      ..sort((a, b) => b.trickiness.compareTo(a.trickiness));
    return list;
  }();

  /// Gegensatzpaare: zwei fast gleich klingende Aussagen derselben Gruppe mit gegenteiliger Lösung.
  /// Jedes Paar kommt nur einmal vor; die richtige Aussage steht zuerst.
  late final List<(Question, Question)> oppositePairs = () {
    final seen = <String>{};
    final pairs = <(Question, Question)>[];
    for (final q in trickyQuestions) {
      final o = q.trapPartner;
      if (o == null) continue;
      final key = q.id < o.id ? '${q.id}-${o.id}' : '${o.id}-${q.id}';
      if (!seen.add(key)) continue;
      pairs.add(q.answer ? (q, o) : (o, q));
    }
    return pairs;
  }();

  /// Bilder für das Bilder-Quiz: Bild → Gruppe mit mindestens einer richtigen Aussage.
  late final List<QuestionGroup> imageGroups = [
    for (final g in groups)
      if (g.images.length == 1 && g.questions.any((q) => q.answer && q.image == g.images.first)) g,
  ];

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

  static const _stopwords = {
    'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem', 'einer', 'eines', 'und', 'oder',
    'auf', 'mit', 'von', 'vom', 'für', 'ist', 'sind', 'wird', 'werden', 'man', 'wenn', 'dass', 'nicht', 'auch',
    'abgebildete', 'abgebildeten', 'verkehrszeichen', 'zeichen', 'dargestellte', 'dargestellten', 'abbildung',
    'steht', 'darf', 'muss', 'kann', 'sich', 'bei', 'nur', 'als', 'aus', 'zum', 'zur', 'wo', 'diese', 'dieser',
  };

  static Set<String> _tokens(String s) => {
        for (final w in s.toLowerCase().split(RegExp(r'[^a-zäöüß0-9]+')))
          if (w.length >= 3 && !_stopwords.contains(w)) w,
      };

  /// Vergleicht jede Aussage mit den Aussagen gegenteiliger Lösung in ihrer Gruppe (Jaccard-Ähnlichkeit).
  static void _computeTrickiness(List<QuestionGroup> groups) {
    for (final g in groups) {
      final tokens = {for (final q in g.questions) q.id: _tokens(q.de)};
      for (final q in g.questions) {
        final a = tokens[q.id]!;
        var best = 0.0;
        Question? partner;
        for (final o in g.questions) {
          if (o.answer == q.answer) continue;
          final b = tokens[o.id]!;
          final union = a.union(b).length;
          if (union == 0) continue;
          final sim = a.intersection(b).length / union;
          if (sim > best) {
            best = sim;
            partner = o;
          }
        }
        q.trickiness = best;
        q.trapPartner = partner;
      }
    }
  }
}
