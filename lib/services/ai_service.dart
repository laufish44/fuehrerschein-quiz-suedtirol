import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
  /// [hint] ist die Offline-Erklärung der App (falls vorhanden) – sie verhindert erfundene Details.
  static String buildPrompt(Question q, {required bool italian, bool forLink = true, String? hint}) {
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
      if (hint != null && hint.trim().isNotEmpty) b.writeln('Nota del libro di teoria: $hint');
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
      if (hint != null && hint.trim().isNotEmpty) b.writeln('Hinweis aus dem Theoriebuch: $hint');
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
  /// Gibt eine Warnung zurück, wenn der Schlüssel zwar gültig ist, Gemini aber gerade
  /// überlastet ist oder das Limit erreicht wurde.
  static Future<AiException?> testGeminiKey(String apiKey, String model) async {
    try {
      await _generate(
        apiKey: apiKey,
        model: model,
        timeout: const Duration(seconds: 30),
        allowFallback: false,
        body: (model, thinking) => {
          'contents': [
            {
              'parts': [
                {'text': 'Antworte nur mit OK.'},
              ],
            },
          ],
          'generationConfig': {if (thinking) ..._thinkingConfig(model)},
        },
      );
      return null;
    } on AiException catch (e) {
      // Bei diesen Fehlern hat Google den Schlüssel bereits akzeptiert.
      if (e.kind == AiErrorKind.overloaded ||
          e.kind == AiErrorKind.rateLimit ||
          e.kind == AiErrorKind.dailyQuota ||
          e.kind == AiErrorKind.server) {
        return e;
      }
      rethrow;
    }
  }

  /// Testet den Schlüssel und liefert einen Text für die Oberfläche (✅ / ⚠️).
  static Future<String> keyTestStatus(String apiKey, String model, {required bool italian}) async {
    if (apiKey.trim().isEmpty) return italian ? '⚠️ Inserisci prima una chiave.' : '⚠️ Bitte zuerst einen Schlüssel eintragen.';
    try {
      final warning = await testGeminiKey(apiKey, model);
      if (warning == null) return italian ? '✅ La chiave funziona!' : '✅ Der Schlüssel funktioniert!';
      return italian
          ? '✅ La chiave è valida. ⚠️ Però in questo momento: ${warning.message(italian: true)}'
          : '✅ Der Schlüssel ist gültig. ⚠️ Aber gerade: ${warning.message(italian: false)}';
    } on AiException catch (e) {
      return '⚠️ ${e.message(italian: italian)}';
    } catch (e) {
      return '⚠️ $e';
    }
  }

  /// Chat über die Gemini-API mit dem eigenen (kostenlosen) Key des Nutzers.
  /// Das Bild der Frage wird mitgeschickt. Bei Überlastung wird automatisch
  /// erneut versucht und notfalls auf ein kleineres Modell ausgewichen;
  /// [onRetry] meldet das der Oberfläche.
  static Future<String> geminiChat({
    required String apiKey,
    required String model,
    required Question question,
    required bool italian,
    required List<AiMessage> history,
    String? hint,
    void Function(AiRetry retry)? onRetry,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': buildPrompt(question, italian: italian, forLink: false, hint: hint)},
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
            'in modo conciso (max. 150 parole se non richiesto altrimenti). La risposta ufficiale indicata è sempre corretta. '
            'Non inventare dettagli della figura né numeri di articoli: se non sei sicuro, ometti il numero.'
        : 'Du bist ein geduldiger, genauer Fahrlehrer in Südtirol. Antworte auf Deutsch, knapp '
            '(max. 150 Wörter, außer der Nutzer will mehr). Die angegebene offizielle Antwort ist immer korrekt. '
            'Erfinde keine Details zum Bild und keine Artikelnummern – wenn du dir nicht sicher bist, lass die Nummer weg.';
    final res = await _generate(
      apiKey: apiKey,
      model: model,
      timeout: const Duration(seconds: 30),
      onRetry: onRetry,
      body: (model, thinking) => {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': contents,
        'generationConfig': {'temperature': 0.4, if (thinking) ..._thinkingConfig(model)},
      },
    );
    return _answerText(res);
  }

  // ---------- Gemini-Anfragen mit Wiederholung ----------

  /// Wenig „Nachdenken“: deutlich schnellere Antworten, für kurze Erklärungen reicht das.
  /// Die Lite-Modelle denken von sich aus nur minimal – da wird nichts mitgeschickt.
  static Map<String, dynamic> _thinkingConfig(String model) => model.contains('lite')
      ? const {}
      : const {
          'thinkingConfig': {'thinkingLevel': 'low'},
        };

  /// Ausweichmodelle, wenn das gewählte Modell überlastet ist, nicht antwortet oder sein Limit
  /// erreicht hat (die kostenlosen Limits gelten pro Modell). Gemessen im Oktober 2026:
  /// Lite ~2 s, 3.6-flash ~6–8 s, gemini-flash-latest (3.8) oft über 2 Minuten.
  static const _fallbackModels = ['gemini-flash-lite-latest', 'gemini-3.6-flash'];

  static final _random = Random();

  /// Antwortet das erste Modell bis dahin nicht, wird das zweite parallel gefragt.
  /// Normal antwortet Gemini in 1–4 s, einzelne Anfragen hängen bei hoher Last aber 30 s und mehr.
  static const hedgeDelay = Duration(seconds: 6);

  /// Fehler, bei denen weder Warten noch ein anderes Modell hilft.
  static const _fatal = {
    AiErrorKind.invalidKey,
    AiErrorKind.payment,
    AiErrorKind.badRequest,
    AiErrorKind.blocked,
  };

  static Future<Map<String, dynamic>> _generate({
    required String apiKey,
    required String model,
    required Map<String, dynamic> Function(String model, bool thinking) body,
    required Duration timeout,
    bool allowFallback = true,
    void Function(AiRetry retry)? onRetry,
  }) async {
    final primary = model.trim().isEmpty ? AppConfig.defaultGeminiModel : model.trim();
    final models = [primary, if (allowFallback) ..._fallbackModels.where((m) => m != primary)];
    final started = DateTime.now();
    var thinking = true;
    AiException? primaryError;
    AiException? lastError;

    // Erste Runde: schnelles Modell, bei Fehler oder Langsamkeit sofort bzw. parallel das zweite.
    if (models.length > 1) {
      try {
        return await _hedged(apiKey, models[0], models[1], body, timeout, onRetry);
      } on AiException catch (e) {
        // Kein Internet, Zeitüberschreitung bei beiden oder ein endgültiger Fehler: nicht weiter warten.
        if (_fatal.contains(e.kind) || e.kind == AiErrorKind.network || e.kind == AiErrorKind.timeout) rethrow;
        primaryError = e;
        lastError = e;
        if (e.kind == AiErrorKind.thinkingUnsupported) {
          thinking = false;
        } else if (const {AiErrorKind.overloaded, AiErrorKind.server, AiErrorKind.rateLimit}.contains(e.kind)) {
          // Beide überlastet: kurz warten, dann der Reihe nach erneut versuchen.
          final retryAfter = e.retryAfter;
          final base = retryAfter != null && retryAfter <= const Duration(seconds: 20) ? retryAfter : const Duration(seconds: 2);
          final wait = base + Duration(milliseconds: _random.nextInt(1000));
          onRetry?.call(AiRetry(kind: e.kind, attempt: 2, wait: wait, model: models[0]));
          await Future.delayed(wait);
        }
      }
    }

    for (var mi = 0; mi < models.length; mi++) {
      final m = models[mi];
      final maxAttempts = mi == 0 ? 3 : 2;
      var attempt = 1;
      while (attempt <= maxAttempts) {
        try {
          return await _post(apiKey, m, body(m, thinking), timeout);
        } on AiException catch (e) {
          if (e.kind == AiErrorKind.thinkingUnsupported && thinking) {
            // Ältere oder selbst gewählte Modelle kennen die Einstellung nicht.
            thinking = false;
            continue;
          }
          lastError = e;
          if (mi == 0) primaryError = e;

          final tooLong = DateTime.now().difference(started) > const Duration(seconds: 100);
          // Fehler, bei denen Warten nichts bringt: sofort melden.
          if (_fatal.contains(e.kind) || e.kind == AiErrorKind.thinkingUnsupported) {
            throw mi == 0 ? e : (primaryError ?? e);
          }
          // Ohne Internet hilft auch ein anderes Modell nicht.
          if (e.kind == AiErrorKind.network && attempt >= 2) rethrow;
          // Modell gibt es nicht, kein Zugriff, Tageslimit oder keine Antwort in der Zeit:
          // nächstes (kleineres, schnelleres) Modell probieren.
          final nextModel = const {
            AiErrorKind.modelNotFound,
            AiErrorKind.noPermission,
            AiErrorKind.dailyQuota,
            AiErrorKind.timeout,
          }.contains(e.kind);
          // Minutenlimit mit langer Wartezeit: lieber gleich ausweichen.
          final longWait = e.kind == AiErrorKind.rateLimit && (e.retryAfter ?? Duration.zero) > const Duration(seconds: 20);
          if (nextModel || longWait || attempt >= maxAttempts || tooLong) break;

          final base = e.kind == AiErrorKind.rateLimit && e.retryAfter != null
              ? e.retryAfter!
              : Duration(seconds: attempt == 1 ? 2 : 5);
          final wait = base + Duration(milliseconds: _random.nextInt(1000));
          onRetry?.call(AiRetry(kind: e.kind, attempt: attempt + 1, wait: wait, model: m));
          await Future.delayed(wait);
          attempt++;
        }
      }
      if (DateTime.now().difference(started) > const Duration(seconds: 100)) break;
      if (mi + 1 < models.length) {
        onRetry?.call(AiRetry(kind: lastError!.kind, attempt: 1, wait: Duration.zero, model: models[mi + 1], switchedModel: true));
      }
    }
    // Wenn das eigene Modell nur „nicht gefunden“ war, ist der Fehler des Ausweichmodells aussagekräftiger.
    if (primaryError == null || primaryError.kind == AiErrorKind.modelNotFound) throw lastError!;
    throw primaryError;
  }

  /// Fragt [first]; schlägt das fehl oder dauert es länger als [hedgeDelay], wird zusätzlich
  /// [second] gefragt. Die erste erfolgreiche Antwort gewinnt, die andere wird ignoriert.
  static Future<Map<String, dynamic>> _hedged(
    String apiKey,
    String first,
    String second,
    Map<String, dynamic> Function(String model, bool thinking) body,
    Duration timeout,
    void Function(AiRetry retry)? onRetry,
  ) {
    final done = Completer<Map<String, dynamic>>();
    var running = 0;
    var secondStarted = false;
    AiException? firstError;
    Timer? timer;

    void finishWithError(AiException e) {
      timer?.cancel();
      if (!done.isCompleted) done.completeError(e);
    }

    late void Function(AiErrorKind why, {required bool parallel}) startSecond;

    void launch(String model) {
      running++;
      _post(apiKey, model, body(model, true), timeout).then((res) {
        timer?.cancel();
        if (!done.isCompleted) done.complete(res);
      }, onError: (Object err) {
        running--;
        final e = err is AiException ? err : AiException(AiErrorKind.network, detail: '$err', model: model);
        firstError ??= e;
        if (done.isCompleted) return;
        if (_fatal.contains(e.kind) || e.kind == AiErrorKind.thinkingUnsupported) {
          finishWithError(e);
        } else if (!secondStarted) {
          startSecond(e.kind, parallel: false);
        } else if (running == 0) {
          finishWithError(firstError!);
        }
      });
    }

    startSecond = (why, {required parallel}) {
      if (secondStarted || done.isCompleted) return;
      secondStarted = true;
      timer?.cancel();
      onRetry?.call(AiRetry(kind: why, attempt: 1, wait: Duration.zero, model: second, switchedModel: true, parallel: parallel));
      launch(second);
    };

    launch(first);
    timer = Timer(hedgeDelay, () => startSecond(AiErrorKind.timeout, parallel: true));
    return done.future;
  }

  static Future<Map<String, dynamic>> _post(String apiKey, String model, Map<String, dynamic> body, Duration timeout) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey.trim()},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException(AiErrorKind.timeout, model: model);
    } catch (e) {
      // Kein Internet, DNS- oder TLS-Fehler (http meldet sie als ClientException).
      throw AiException(AiErrorKind.network, detail: e.toString(), model: model);
    }

    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // z. B. eine HTML-Fehlerseite eines Proxys
    }
    if (res.statusCode == 200 && json != null) return json;
    throw AiException.fromResponse(res.statusCode, json, model);
  }

  static String _answerText(Map<String, dynamic> res) {
    final candidates = res['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final blockReason = (res['promptFeedback'] as Map?)?['blockReason'];
      throw AiException(blockReason != null ? AiErrorKind.blocked : AiErrorKind.empty, detail: blockReason?.toString());
    }
    final first = candidates.first as Map;
    final parts = (first['content'] as Map?)?['parts'] as List? ?? const [];
    final text = parts.where((p) => p is Map && p['thought'] != true).map((p) => (p as Map)['text'] ?? '').join().trim();
    if (text.isNotEmpty) return text;
    final reason = first['finishReason']?.toString();
    if (reason != null && const {'SAFETY', 'PROHIBITED_CONTENT', 'BLOCKLIST', 'SPII', 'RECITATION'}.contains(reason)) {
      throw AiException(AiErrorKind.blocked, detail: reason);
    }
    throw AiException(AiErrorKind.empty, detail: reason);
  }
}

enum AiErrorKind {
  overloaded,
  rateLimit,
  dailyQuota,
  invalidKey,
  noPermission,
  payment,
  modelNotFound,
  thinkingUnsupported,
  badRequest,
  blocked,
  empty,
  timeout,
  network,
  server,
}

/// Meldung an die Oberfläche: es wird gleich erneut versucht.
class AiRetry {
  final AiErrorKind kind;
  final int attempt;
  final Duration wait;
  final String model;
  final bool switchedModel;

  /// Das erste Modell läuft weiter, das zweite wird zusätzlich gefragt.
  final bool parallel;
  const AiRetry({
    required this.kind,
    required this.attempt,
    required this.wait,
    required this.model,
    this.switchedModel = false,
    this.parallel = false,
  });

  String message({required bool italian}) {
    if (parallel) {
      return italian
          ? 'Gemini è lento – chiedo anche al modello $model …'
          : 'Gemini antwortet langsam – frage zusätzlich das Modell $model …';
    }
    final why = switch (kind) {
      AiErrorKind.overloaded => italian ? 'Gemini è sovraccarico' : 'Gemini ist gerade überlastet',
      AiErrorKind.rateLimit => italian ? 'Troppe richieste al minuto' : 'Zu viele Anfragen pro Minute',
      AiErrorKind.dailyQuota => italian ? 'Limite giornaliero raggiunto' : 'Tageslimit erreicht',
      AiErrorKind.timeout => italian ? 'Gemini non risponde' : 'Gemini antwortet nicht',
      AiErrorKind.network => italian ? 'Problema di connessione' : 'Verbindungsproblem',
      AiErrorKind.modelNotFound => italian ? 'Modello non disponibile' : 'Modell nicht verfügbar',
      _ => italian ? 'Errore di Google' : 'Fehler bei Google',
    };
    if (switchedModel) {
      return italian ? '$why – provo con il modello $model …' : '$why – versuche es mit dem Modell $model …';
    }
    final s = (wait.inMilliseconds / 1000).ceil();
    return italian ? '$why – nuovo tentativo tra $s s …' : '$why – neuer Versuch in $s s …';
  }
}

class AiException implements Exception {
  final AiErrorKind kind;
  final String? detail;
  final Duration? retryAfter;
  final String? model;
  final int? status;

  const AiException(this.kind, {this.detail, this.retryAfter, this.model, this.status});

  factory AiException.fromResponse(int status, Map<String, dynamic>? json, String model) {
    final error = json?['error'] as Map?;
    final message = error?['message']?.toString() ?? '';
    final details = (error?['details'] as List?) ?? const [];
    final lower = message.toLowerCase();
    final allText = '${lower}_${jsonEncode(details).toLowerCase()}';

    Duration? retryAfter;
    for (final d in details) {
      final delay = d is Map ? d['retryDelay']?.toString() : null; // z. B. "37s"
      final secs = delay == null ? null : double.tryParse(delay.replaceAll('s', ''));
      if (secs != null) retryAfter = Duration(milliseconds: (secs * 1000).round());
    }
    if (retryAfter == null) {
      final m = RegExp(r'retry in ([0-9.]+)\s*s').firstMatch(lower);
      final secs = m == null ? null : double.tryParse(m.group(1)!);
      if (secs != null) retryAfter = Duration(milliseconds: (secs * 1000).round());
    }

    AiErrorKind kind;
    if (status == 429) {
      kind = allText.contains('perday') || allText.contains('per day') || allText.contains('quota_exceeded')
          ? AiErrorKind.dailyQuota
          : AiErrorKind.rateLimit;
    } else if (status == 503) {
      kind = AiErrorKind.overloaded;
    } else if (status == 504 || status == 408) {
      kind = AiErrorKind.timeout;
    } else if (status >= 500) {
      kind = AiErrorKind.server;
    } else if (status == 401 || lower.contains('api key not valid') || allText.contains('api_key_invalid') || lower.contains('leaked')) {
      kind = AiErrorKind.invalidKey;
    } else if (status == 402) {
      kind = AiErrorKind.payment;
    } else if (status == 403) {
      kind = AiErrorKind.noPermission;
    } else if (status == 404) {
      kind = AiErrorKind.modelNotFound;
    } else if (status == 400 && lower.contains('thinking')) {
      kind = AiErrorKind.thinkingUnsupported;
    } else {
      kind = AiErrorKind.badRequest;
    }
    return AiException(
      kind,
      detail: message.isEmpty ? null : message,
      retryAfter: retryAfter,
      model: model,
      status: status,
    );
  }

  String message({required bool italian}) {
    final code = status == null ? '' : ' ($status)';
    return switch (kind) {
      AiErrorKind.overloaded => italian
          ? 'Gemini è sovraccarico in questo momento (troppe richieste a Google). L\'app ha già riprovato più volte. '
              'Riprova tra qualche minuto oppure usa ChatGPT, Claude o Perplexity.'
          : 'Gemini ist gerade überlastet (zu viele Anfragen bei Google). Die App hat es schon mehrmals versucht. '
              'Probier es in ein paar Minuten nochmal oder nimm solange ChatGPT, Claude oder Perplexity.',
      AiErrorKind.rateLimit => italian
          ? 'Limite gratuito al minuto raggiunto. Aspetta ${_secs(retryAfter, 60)} secondi e riprova.'
          : 'Kostenloses Limit pro Minute erreicht. Warte ${_secs(retryAfter, 60)} Sekunden und versuch es nochmal.',
      AiErrorKind.dailyQuota => italian
          ? 'Il limite giornaliero gratuito della tua chiave Gemini è esaurito. Si azzera la mattina dopo (verso le 9). '
              'Fino ad allora usa ChatGPT, Claude o Perplexity.'
          : 'Das kostenlose Tageslimit deines Gemini-Schlüssels ist aufgebraucht. Es wird am nächsten Morgen (gegen 9 Uhr) '
              'zurückgesetzt. Bis dahin geht ChatGPT, Claude oder Perplexity.',
      AiErrorKind.invalidKey => italian
          ? 'La chiave Gemini non è valida o è stata bloccata. Creane una nuova su Google AI Studio e inseriscila in Impostazioni → Spiegazioni IA.'
          : 'Der Gemini-Schlüssel ist ungültig oder wurde gesperrt. Erstelle in Google AI Studio einen neuen und trage ihn unter Einstellungen → KI-Erklärungen ein.',
      AiErrorKind.noPermission => italian
          ? 'La tua chiave non ha accesso al modello “$model”. Lascia vuoto il campo del modello nelle impostazioni.'
          : 'Dein Schlüssel hat keinen Zugriff auf das Modell „$model“. Lass das Modellfeld in den Einstellungen leer.',
      AiErrorKind.payment => italian
          ? 'Il credito del tuo account Google AI è esaurito.'
          : 'Das Guthaben deines Google-AI-Kontos ist aufgebraucht.',
      AiErrorKind.modelNotFound => italian
          ? 'Il modello “$model” non esiste (più). Lascia vuoto il campo del modello nelle impostazioni.'
          : 'Das Modell „$model“ gibt es nicht (mehr). Lass das Modellfeld in den Einstellungen leer.',
      AiErrorKind.blocked => italian
          ? 'Gemini ha bloccato la risposta per motivi di sicurezza. Prova a riformulare la domanda.'
          : 'Gemini hat die Antwort aus Sicherheitsgründen blockiert. Formuliere die Frage anders.',
      AiErrorKind.empty => italian
          ? 'Gemini non ha dato nessuna risposta. Riprova.'
          : 'Gemini hat keine Antwort geliefert. Versuch es nochmal.',
      AiErrorKind.timeout => italian
          ? 'Gemini non ha risposto in tempo. Riprova.'
          : 'Gemini hat zu lange nicht geantwortet. Versuch es nochmal.',
      AiErrorKind.network => italian
          ? 'Nessuna connessione a Gemini. Controlla la connessione a Internet.'
          : 'Keine Verbindung zu Gemini. Prüfe deine Internetverbindung.',
      AiErrorKind.server => italian
          ? 'Errore temporaneo di Google$code. Riprova tra poco.'
          : 'Vorübergehender Fehler bei Google$code. Versuch es gleich nochmal.',
      AiErrorKind.thinkingUnsupported || AiErrorKind.badRequest => italian
          ? 'Gemini ha rifiutato la richiesta$code: ${detail ?? ''}'
          : 'Gemini hat die Anfrage abgelehnt$code: ${detail ?? ''}',
    };
  }

  static int _secs(Duration? d, int fallback) => d == null ? fallback : (d.inMilliseconds / 1000).ceil();

  @override
  String toString() => message(italian: false);
}
