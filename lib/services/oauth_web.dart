bool get loopbackSupported => false;

typedef OAuthTokens = ({String accessToken, String refreshToken, int expiresIn});

Future<OAuthTokens> signInWithLoopback({
  required String clientId,
  required String clientSecret,
  required String scope,
}) =>
    throw UnsupportedError('Google-Drive-Sync gibt es nur in der Android- und Windows-App.');
