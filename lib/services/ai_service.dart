import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/question_bank.dart';

class AiServiceInfo {
  final String id;
  final String name;
  final String? urlPrefix; // null = kein Vorausfüllen möglich
  final String homeUrl;

  const AiServiceInfo(this.id, this.name, this.urlPrefix, this.homeUrl);
}

const aiServices = [
  AiServiceInfo('chatgpt', 'ChatGPT', 'https://chatgpt.com/?q=', 'https://chatgpt.com/'),
  AiServiceInfo('claude', 'Claude', 'https://claude.ai/new?q=', 'https://claude.ai/new'),
  AiServiceInfo('perplexity', 'Perplexity', 'https://www.perplexity.ai/search?q=', 'https://www.perplexity.ai/'),
  AiServiceInfo('gemini', 'Gemini', null, 'https://gemini.google.com/app'),
];

AiServiceInfo aiServiceById(String id) => aiServices.firstWhere((s) => s.id == id, orElse: () => aiServices.first);

class AiMessage {
  final bool fromUser;
  final String text;
  const AiMessage(this.fromUser, this.text);
}

class AiService {
  /// Erstellt die Frage an die KI. Da Links keine Bilder mitschicken können, werden
  /// die laut offizieller Liste richtigen Aussagen zum selben Bild als Beschreibung mitgegeben.
  static String buildPrompt(Question q, {required bool italian, bool forLink = true}) {
    final correct = q.answer;
    final sameImage = q.group.questions.where((o) => o.id != q.id && o.answer).take(6).toList();
    final b = StringBuffer();
    if (italian) {
      b.writeln('Sto studiando per l\'esame teorico della patente B in Italia (Alto Adige).');
      b.writeln('Domanda vero/falso (n. ${q.id}, capitolo "${q.chapter.it}"):');
      b.writeln('«${q.it}»');
      b.writeln('Risposta ufficiale: ${correct ? 'VERO' : 'FALSO'}.');
      if (q.image != null && forLink) {
        b.writeln('La domanda si riferisce a una figura che non posso allegare. '
            'Secondo il listato ministeriale, sulla stessa figura sono VERE queste affermazioni:');
        for (final o in sameImage) {
          b.writeln('- ${o.it}');
        }
      }
      b.writeln('Spiegami in modo breve e chiaro perché la risposta è ${correct ? 'vera' : 'falsa'}, '
          'citando la regola del Codice della Strada italiano, e dammi un trucco per ricordarla.');
    } else {
      b.writeln('Ich lerne für die theoretische Führerscheinprüfung Klasse B in Italien (Südtirol, auf Deutsch).');
      b.writeln('Richtig/Falsch-Frage (Nr. ${q.id}, Kapitel "${q.chapter.de}"):');
      b.writeln('«${q.de}»');
      b.writeln('Offizielle Antwort: ${correct ? 'RICHTIG' : 'FALSCH'}.');
      if (q.image != null && forLink) {
        b.writeln('Die Frage bezieht sich auf ein Bild, das ich nicht mitschicken kann. '
            'Laut offizieller Fragenliste sind zum selben Bild diese Aussagen RICHTIG:');
        for (final o in sameImage) {
          b.writeln('- ${o.de}');
        }
      }
      b.writeln('Erkläre mir kurz und verständlich, warum die Aussage ${correct ? 'richtig' : 'falsch'} ist, '
          'nenne die Regel aus der italienischen Straßenverkehrsordnung und gib mir eine Eselsbrücke.');
    }
    return b.toString().trim();
  }

  /// Öffnet den gewählten KI-Dienst mit der vorausgefüllten Frage.
  /// Gibt false zurück, wenn der Text stattdessen in die Zwischenablage kopiert wurde.
  static Future<bool> openInService(AiServiceInfo service, String prompt) async {
    if (service.urlPrefix == null) {
      await Clipboard.setData(ClipboardData(text: prompt));
      await launchUrl(Uri.parse(service.homeUrl), mode: LaunchMode.externalApplication);
      return false;
    }
    final url = Uri.parse('${service.urlPrefix}${Uri.encodeComponent(prompt)}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
    return true;
  }

  /// Prüft, ob ein Gemini-Schlüssel funktioniert (kurze Testanfrage).
  static Future<void> testGeminiKey(String apiKey, String model) async {
    final m = model.trim().isEmpty ? AppConfig.defaultGeminiModel : model.trim();
    final res = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey.trim()},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': 'Antworte nur mit OK.'},
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      Object? message;
      if (body is Map && body['error'] is Map) message = (body['error'] as Map)['message'];
      throw Exception(message ?? 'HTTP ${res.statusCode}');
    }
  }

  /// Chat über die Gemini-API mit dem eigenen (kostenlosen) Key des Nutzers.
  /// Das Bild der Frage wird mitgeschickt.
  static Future<String> geminiChat({
    required String apiKey,
    required String model,
    required Question question,
    required bool italian,
    required List<AiMessage> history,
  }) async {
    final m = model.trim().isEmpty ? AppConfig.defaultGeminiModel : model.trim();
    final parts = <Map<String, dynamic>>[
      {'text': buildPrompt(question, italian: italian, forLink: false)},
    ];
    if (question.imageAsset != null) {
      final bytes = await rootBundle.load(question.imageAsset!);
      parts.add({
        'inline_data': {'mime_type': 'image/webp', 'data': base64Encode(bytes.buffer.asUint8List())},
      });
    }
    final contents = <Map<String, dynamic>>[
      {'role': 'user', 'parts': parts},
      for (final h in history) {'role': h.fromUser ? 'user' : 'model', 'parts': [{'text': h.text}]},
    ];
    final system = italian
        ? 'Sei un istruttore di scuola guida in Alto Adige, paziente e preciso. Rispondi in italiano, '
            'in modo conciso (max. 150 parole se non richiesto altrimenti). La risposta ufficiale indicata è sempre corretta.'
        : 'Du bist ein geduldiger, genauer Fahrlehrer in Südtirol. Antworte auf Deutsch, knapp '
            '(max. 150 Wörter, außer der Nutzer will mehr). Die angegebene offizielle Antwort ist immer korrekt.';
    final res = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey.trim()},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': system},
              ],
            },
            'contents': contents,
            'generationConfig': {'temperature': 0.4},
          }),
        )
        .timeout(const Duration(seconds: 60));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = (body['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}';
      throw Exception(msg);
    }
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) throw Exception('Keine Antwort erhalten.');
    final contentParts = ((candidates.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
    return contentParts.map((p) => (p as Map)['text'] ?? '').join().trim();
  }
}
