import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/local_settings.dart';
import 'data/progress.dart';
import 'data/question_bank.dart';
import 'data/session_builder.dart';
import 'data/user_data.dart';
import 'services/storage.dart';

const _dataFile = 'lernstand.json';
const _localFile = 'geraet.json';

/// Zentraler App-Zustand: Fragen, Lernstand, Einstellungen.
class AppState extends ChangeNotifier {
  final QuestionBank bank;
  UserData data;
  LocalSettings local;
  Progress? _progress;
  Timer? _saveTimer;

  /// Läuft gerade eine Übung/Prüfung? (Updates werden dann nicht installiert.)
  bool sessionActive = false;

  /// Wird aufgerufen, wenn sich der Lernstand geändert hat (für den Sync).
  void Function()? onDataChanged;

  AppState._(this.bank, this.data, this.local);

  static Future<AppState> load() async {
    final bank = await QuestionBank.load();
    UserData data;
    LocalSettings local;
    try {
      final raw = await Storage.read(_dataFile);
      data = raw == null ? UserData() : UserData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      data = UserData();
    }
    try {
      final raw = await Storage.read(_localFile);
      local = raw == null ? LocalSettings() : LocalSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      local = LocalSettings();
    }
    final state = AppState._(bank, data, local);
    await state._saveLocal(); // neue Geräte-ID sofort festhalten
    return state;
  }

  Progress get progress => _progress ??= Progress(bank, data);

  SyncedSettings get settings => data.settings;
  bool get italianUi => settings.uiLanguage == 'it';
  bool get italianQuestions => settings.questionLanguage == 'it';

  Set<int> get favoriteIds => {for (final e in data.favorites.entries) if (e.value.$2) e.key};
  bool isFavorite(Question q) => data.favorites[q.id]?.$2 ?? false;
  String note(Question q) => data.notes[q.id]?.$2 ?? '';
  List<Question> get notedQuestions => [
        for (final e in data.notes.entries)
          if (e.value.$2.isNotEmpty && bank.byId[e.key] != null) bank.byId[e.key]!,
      ];

  SessionBuilder get builder => SessionBuilder(bank, progress, favoriteIds);

  void _changed({bool sync = true}) {
    _progress = null;
    notifyListeners();
    _scheduleSave();
    if (sync) onDataChanged?.call();
  }

  void recordAnswer(Question q, bool correct, {int mode = AnswerMode.practice}) {
    final list = data.events[local.deviceId] ??= [];
    var ts = nowSeconds();
    // Gleicher Zeitstempel für dieselbe Frage würde beim Zusammenführen zusammenfallen.
    if (list.isNotEmpty && list.last.qid == q.id && list.last.ts >= ts) ts = list.last.ts + 1;
    list.add(AnswerEvent(q.id, ts, correct, mode));
    _changed(sync: false);
  }

  void addStudySeconds(int seconds) {
    if (seconds <= 0) return;
    final m = data.studySeconds[local.deviceId] ??= {};
    final k = dayKey(DateTime.now());
    m[k] = (m[k] ?? 0) + seconds;
    _progress = null;
    _scheduleSave();
  }

  void saveExam(ExamRecord exam) {
    data.exams[exam.id] = exam;
    final list = data.events[local.deviceId] ??= [];
    var ts = exam.start;
    for (var i = 0; i < exam.qids.length; i++) {
      final q = bank.byId[exam.qids[i]];
      if (q == null || exam.answers[i] == -1) continue;
      list.add(AnswerEvent(q.id, ts++, (exam.answers[i] == 1) == q.answer, AnswerMode.exam));
    }
    list.sort((a, b) => a.ts.compareTo(b.ts));
    _changed();
  }

  void toggleFavorite(Question q) {
    data.favorites[q.id] = (nowSeconds(), !isFavorite(q));
    _changed();
  }

  void setNote(Question q, String text) {
    data.notes[q.id] = (nowSeconds(), text.trim());
    _changed();
  }

  void updateSettings(void Function(SyncedSettings s) change) {
    change(data.settings);
    data.settingsTs = nowSeconds();
    _changed();
  }

  void updateLocal(void Function(LocalSettings l) change) {
    change(local);
    notifyListeners();
    _saveLocal();
  }

  /// Ein Sitzungsende (Übung/Prüfung) löst einen Sync aus.
  void sessionFinished() {
    sessionActive = false;
    onDataChanged?.call();
    notifyListeners();
  }

  void resetProgress() {
    data.resetTs = nowSeconds() + 1;
    data.prune();
    data.favorites.clear();
    data.notes.clear();
    _changed();
  }

  // ---------- Export / Import / Sync ----------

  String exportJson() => const JsonEncoder.withIndent(' ').convert({
        'app': 'fuehrerschein-quiz-suedtirol',
        'exported': DateTime.now().toIso8601String(),
        'data': data.toJson(),
      });

  /// Führt einen exportierten Stand mit dem aktuellen zusammen.
  bool importJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final other = UserData.fromJson((j['data'] ?? j) as Map<String, dynamic>);
    final changed = data.mergeFrom(other);
    if (changed) _changed(sync: true);
    return changed;
  }

  /// Für den Drive-Sync: fremden Stand einmischen, ohne erneut einen Sync auszulösen.
  bool mergeRemote(UserData remote) {
    final changed = data.mergeFrom(remote);
    if (changed) _changed(sync: false);
    return changed;
  }

  // ---------- Speichern ----------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    await Storage.write(_dataFile, jsonEncode(data.toJson()));
  }

  Future<void> _saveLocal() => Storage.write(_localFile, jsonEncode(local.toJson()));
}

extension AppContext on BuildContext {
  AppState get app => read<AppState>();

  /// Zweisprachiger Text je nach eingestellter App-Sprache.
  String tr(String de, String it) => watch<AppState>().italianUi ? it : de;

  /// Wie [tr], aber ohne neu zu zeichnen (für Callbacks).
  String trNow(String de, String it) => read<AppState>().italianUi ? it : de;
}
