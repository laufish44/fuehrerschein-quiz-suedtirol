import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

bool get loopbackSupported => Platform.isAndroid || Platform.isWindows;

typedef OAuthTokens = ({String accessToken, String refreshToken, int expiresIn});

String _randomString(int length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

/// OAuth 2.0 für installierte Apps: Browser öffnen, Antwort über einen lokalen
/// Mini-Server auf 127.0.0.1 empfangen (mit PKCE).
Future<OAuthTokens> signInWithLoopback({
  required String clientId,
  required String clientSecret,
  required String scope,
}) async {
  final verifier = _randomString(64);
  final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
  final state = _randomString(24);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirect = 'http://127.0.0.1:${server.port}';
  try {
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': scope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
    });
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      throw Exception('Browser konnte nicht geöffnet werden.');
    }

    String? code;
    String? error;
    await for (final req in server.timeout(const Duration(minutes: 5))) {
      final params = req.uri.queryParameters;
      if (!params.containsKey('code') && !params.containsKey('error')) {
        req.response.statusCode = 404;
        await req.response.close();
        continue;
      }
      if (params['state'] != state) {
        error = 'Ungültige Antwort (state).';
      } else {
        code = params['code'];
        error = params['error'];
      }
      final ok = code != null;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
          '<body style="font-family:sans-serif;text-align:center;padding:48px">'
          '<h2>${ok ? '✅ Verbunden!' : '❌ Abgebrochen'}</h2>'
          '<p>${ok ? 'Du kannst dieses Fenster schließen und zur App zurückkehren.<br>Ora puoi tornare all\'app.' : 'Bitte in der App erneut versuchen.'}</p>'
          '</body>');
      await req.response.close();
      break;
    }
    if (code == null) throw Exception(error ?? 'Anmeldung abgebrochen.');

    final res = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'code': code,
      'client_id': clientId,
      'client_secret': clientSecret,
      'redirect_uri': redirect,
      'grant_type': 'authorization_code',
      'code_verifier': verifier,
    });
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || j['refresh_token'] == null) {
      throw Exception('Anmeldung fehlgeschlagen: ${j['error_description'] ?? j['error'] ?? res.statusCode}');
    }
    return (
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      expiresIn: j['expires_in'] as int? ?? 3600,
    );
  } on TimeoutException {
    throw Exception('Zeit für die Anmeldung abgelaufen.');
  } finally {
    await server.close(force: true);
  }
}
