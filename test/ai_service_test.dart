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

  Future<String> chat(MockClient client, {List<AiRetry>? retries}) => http.runWithClient(
        () => AiService.geminiChat(
          apiKey: 'test-key',
          model: '',
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
    test('Überlastung: erneuter Versuch klappt', () async {
      var calls = 0;
      final retries = <AiRetry>[];
      final client = MockClient((r) async => ++calls == 1 ? _error(503, 'The model is overloaded.') : _answer('Erklärung'));
      expect(await chat(client, retries: retries), 'Erklärung');
      expect(calls, 2);
      expect(retries.single.kind, AiErrorKind.overloaded);
    });

    test('Dauerhaft überlastet: weicht auf kleineres Modell aus', () async {
      final models = <String>[];
      final retries = <AiRetry>[];
      final client = MockClient((r) async {
        models.add(_model(r));
        return models.length <= 3 ? _error(503, 'The model is overloaded.') : _answer('vom kleinen Modell');
      });
      expect(await chat(client, retries: retries), 'vom kleinen Modell');
      expect(models.take(3).toSet(), {'gemini-flash-latest'});
      expect(models.last, 'gemini-flash-lite-latest');
      expect(retries.last.switchedModel, isTrue);
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
      expect(models, ['gemini-flash-latest', 'gemini-flash-lite-latest']);
    });

    test('Modell kennt thinkingLevel nicht: ohne erneut senden', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        return bodies.length == 1 ? _error(400, 'Unknown field: thinking_level is not supported') : _answer('ok');
      });
      expect(await chat(client), 'ok');
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
