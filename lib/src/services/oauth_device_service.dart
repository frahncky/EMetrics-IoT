import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class DeviceAuthorizationSession {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String? verificationUriComplete;
  final int expiresInSeconds;
  final int intervalSeconds;

  const DeviceAuthorizationSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresInSeconds,
    required this.intervalSeconds,
  });
}

class OAuthTokenResult {
  final String accessToken;
  final String tokenType;
  final DateTime? expiresAt;

  const OAuthTokenResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
  });
}

class OAuthDeviceService {
  final http.Client _client;

  OAuthDeviceService({http.Client? client}) : _client = client ?? http.Client();

  Future<DeviceAuthorizationSession> startDeviceAuthorization({
    required Uri deviceEndpoint,
    required String clientId,
    String? scope,
  }) async {
    final response = await _client.post(
      deviceEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        if (scope != null && scope.trim().isNotEmpty) 'scope': scope.trim(),
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Falha ao iniciar OAuth (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return DeviceAuthorizationSession(
      deviceCode: payload['device_code'] as String,
      userCode: payload['user_code'] as String,
      verificationUri: payload['verification_uri'] as String,
      verificationUriComplete: payload['verification_uri_complete'] as String?,
      expiresInSeconds: payload['expires_in'] as int? ?? 900,
      intervalSeconds: payload['interval'] as int? ?? 5,
    );
  }

  Future<OAuthTokenResult> pollForToken({
    required Uri tokenEndpoint,
    required String clientId,
    required DeviceAuthorizationSession session,
  }) async {
    final deadline = DateTime.now().add(
      Duration(seconds: session.expiresInSeconds),
    );
    var intervalSeconds = session.intervalSeconds;

    while (DateTime.now().isBefore(deadline)) {
      final response = await _client.post(
        tokenEndpoint,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': session.deviceCode,
          'client_id': clientId,
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final expiresIn = payload['expires_in'] as int?;
        return OAuthTokenResult(
          accessToken: payload['access_token'] as String,
          tokenType: payload['token_type'] as String? ?? 'Bearer',
          expiresAt: expiresIn == null
              ? null
              : DateTime.now().add(Duration(seconds: expiresIn)),
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final error = payload['error'] as String? ?? 'oauth_error';
      if (error == 'authorization_pending') {
        await Future<void>.delayed(Duration(seconds: intervalSeconds));
        continue;
      }
      if (error == 'slow_down') {
        intervalSeconds++;
        await Future<void>.delayed(Duration(seconds: intervalSeconds));
        continue;
      }
      if (error == 'access_denied') {
        throw StateError('Autorização recusada no provedor OAuth.');
      }
      if (error == 'expired_token') {
        throw StateError('Código OAuth expirado. Inicie novamente.');
      }
      throw StateError('Falha OAuth: $error');
    }

    throw TimeoutException('Tempo esgotado aguardando autorização OAuth.');
  }
}
