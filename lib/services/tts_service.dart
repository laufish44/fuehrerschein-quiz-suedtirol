import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Vorlesen von Fragen und Erklärungen.
class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static String? _language;

  static Future<void> speak(String text, {required bool italian, double rate = 0.5}) async {
    try {
      await _tts.stop();
      final lang = italian ? 'it-IT' : 'de-DE';
      if (_language != lang) {
        await _tts.setLanguage(lang);
        _language = lang;
      }
      // Android erwartet 0..1 (0.5 = normal), Windows/Web 0..2 (1 = normal).
      final r = defaultTargetPlatform == TargetPlatform.android ? rate : rate * 2;
      await _tts.setSpeechRate(r);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS-Fehler: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
