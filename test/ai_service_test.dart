import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuehrerschein_quiz/data/question_bank.dart';
import 'package:fuehrerschein_quiz/services/ai_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _error(int status, String message) => http.Response(
      jsonEncode({
        'error': {'code': status, 'message': message},
      }),
      status,
    );

http.Response _answer(String text) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _model(http.Request r) => r.url.pathSegments.last.split(':').first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Question question;
  setUpAll(() async {
    final bank = await QuestionBank.load();
    question = bank.questions.firstWhere((q) => q.imageAsset == null);
  });

  Future<String> chat(MockClient client, {List<AiRetry>? retries, String model = ''}) => http.runWithClient(
        () => AiService.geminiChat(
          apiKey: 'test-key',
          model: model,
          question: question,
          italian: false,
          history: const [],
          onRetry: retries?.add,
        ),
        () => client,
      );

  group('Fehler erkennen', () {
    test('Überlastung (503)', () {
      final e = AiException.fromResponse(503, {
        'error': {'code': 503, 'message': 'The model is overloaded. Please try again later.', 'status': 'UNAVAILABLE'},
      }, 'm');
      expect(e.kind, AiErrorKind.overloaded);
      expect(e.message(italian: false), contains('überlastet'));
    });

    test('Minutenlimit mit Wartezeit (429)', () {
      final e = AiException.fromResponse(429, {
        'error': {
          'code': 429,
          'message': 'You exceeded your current quota. Please retry in 12.5s.',
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
              'violations': [
                {'quotaId': 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier'},
              ],
            },
            {'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '12s'},
          ],
        },
      }, 'm');
      expect(e.kind, AiErrorKind.rateLimit);
      expect(e.retryAfter, const Duration(seconds: 12));
    });

    test('Tageslimit (429)', () {
      final e = AiException.fromResponse(429, {
        'error': {
          'code': 429,
          'message': 'You exceeded your current quota.',
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
              'violations': [
                {'quotaId': 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'},
              ],
            },
          ],
        },
      }, 'm');
      expect(e.kind, AiErrorKind.dailyQuota);
    });

    test('ungültiger Schlüssel (400)', () {
      final e = AiException.fromResponse(400, {
        'error': {'code': 400, 'message': 'API key not valid. Please pass a valid API key.', 'status': 'INVALID_ARGUMENT'},
      }, 'm');
      expect(e.kind, AiErrorKind.invalidKey);
    });

    test('kein JSON (z. B. Proxy-Fehlerseite)', () {
      expect(AiException.fromResponse(502, null, 'm').kind, AiErrorKind.server);
    });
  });

  group('Wiederholen und Ausweichen', () {
    test('Überlastung: sofort das zweite Modell, ohne Warten', () async {
      final models = <String>[];
      final retries = <AiRetry>[];
      final client = MockClient((r) async {
        models.add(_model(r));
        return models.length == 1 ? _error(503, 'The model is overloaded.') : _answer('Erklärung');
      });
      final sw = Stopwatch()..start();
      expect(await chat(client, retries: retries), 'Erklärung');
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      expect(models, ['gemini-flash-lite-latest', 'gemini-3.6-flash']);
      expect(retries.single.kind, AiErrorKind.overloaded);
      expect(retries.single.switchedModel, isTrue);
    });

    test('Langsame Antwort: zweites Modell wird parallel gefragt', () async {
      final retries = <AiRetry>[];
      final client = MockClient((r) async {
        if (_model(r) == 'gemini-flash-lite-latest') {
          await Future.delayed(const Duration(seconds: 12));
          return _answer('langsam');
        }
        return _answer('schnell');
      });
      final sw = Stopwatch()..start();
      expect(await chat(client, retries: retries), 'schnell');
      expect(sw.elapsed, lessThan(const Duration(seconds: 9)));
      expect(retries.single.parallel, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Beide überlastet: neuer Versuch mit Wartezeit', () async {
      final models = <String>[];
      final retries = <AiRetry>[];
      final client = MockClient((r) async {
        models.add(_model(r));
        return models.length <= 2 ? _error(503, 'The model is overloaded.') : _answer('beim zweiten Mal');
      });
      expect(await chat(client, retries: retries), 'beim zweiten Mal');
      expect(models, ['gemini-flash-lite-latest', 'gemini-3.6-flash', 'gemini-flash-lite-latest']);
      expect(retries.last.wait, greaterThan(Duration.zero));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Tageslimit: sofort anderes Modell, ohne Warten', () async {
      final models = <String>[];
      final client = MockClient((r) async {
        models.add(_model(r));
        return models.length == 1 ? _error(429, 'Quota exceeded: GenerateRequestsPerDay') : _answer('ok');
      });
      final sw = Stopwatch()..start();
      expect(await chat(client), 'ok');
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      expect(models, ['gemini-flash-lite-latest', 'gemini-3.6-flash']);
    });

    test('Lite-Modell bekommt keine Denk-Einstellung, andere schon', () async {
      final bodies = <String, Map<String, dynamic>>{};
      final client = MockClient((r) async {
        bodies[_model(r)] = jsonDecode(r.body) as Map<String, dynamic>;
        return _answer('ok');
      });
      await chat(client);
      await chat(client, model: 'gemini-flash-latest');
      expect((bodies['gemini-flash-lite-latest']!['generationConfig'] as Map).containsKey('thinkingConfig'), isFalse);
      expect((bodies['gemini-flash-latest']!['generationConfig'] as Map).containsKey('thinkingConfig'), isTrue);
    });

    test('Modell kennt thinkingLevel nicht: ohne erneut senden', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        bodies.add(body);
        final withThinking = (body['generationConfig'] as Map).containsKey('thinkingConfig');
        return withThinking ? _error(400, 'Unknown field: thinking_level is not supported') : _answer('ok');
      });
      expect(await chat(client, model: 'gemini-flash-latest'), 'ok');
      expect((bodies.first['generationConfig'] as Map).containsKey('thinkingConfig'), isTrue);
      expect((bodies.last['generationConfig'] as Map).containsKey('thinkingConfig'), isFalse);
    });

    test('ungültiger Schlüssel: kein erneuter Versuch', () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        return _error(400, 'API key not valid. Please pass a valid API key.');
      });
      await expectLater(chat(client), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.invalidKey)));
      expect(calls, 1);
    });

    test('kein Internet: zwei Versuche, dann klare Meldung', () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        throw http.ClientException('Failed host lookup');
      });
      await expectLater(chat(client), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)));
      expect(calls, 2);
    });

    test('blockierte Antwort wird erkannt', () async {
      final client = MockClient((r) async => http.Response(
            jsonEncode({
              'promptFeedback': {'blockReason': 'SAFETY'},
            }),
            200,
          ));
      await expectLater(chat(client), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.blocked)));
    });
  });
}
