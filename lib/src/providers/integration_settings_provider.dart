import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IntegrationSettings {
  final bool enabled;
  final String baseUrl;
  final String metricsPath;
  final String apiKey;
  final bool oauthEnabled;
  final String oauthClientId;
  final String oauthScope;
  final String oauthDeviceEndpoint;
  final String oauthTokenEndpoint;
  final String oauthAccessToken;
  final String oauthTokenType;
  final DateTime? oauthExpiresAt;

  const IntegrationSettings({
    required this.enabled,
    required this.baseUrl,
    required this.metricsPath,
    required this.apiKey,
    required this.oauthEnabled,
    required this.oauthClientId,
    required this.oauthScope,
    required this.oauthDeviceEndpoint,
    required this.oauthTokenEndpoint,
    required this.oauthAccessToken,
    required this.oauthTokenType,
    required this.oauthExpiresAt,
  });

  IntegrationSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? metricsPath,
    String? apiKey,
    bool? oauthEnabled,
    String? oauthClientId,
    String? oauthScope,
    String? oauthDeviceEndpoint,
    String? oauthTokenEndpoint,
    String? oauthAccessToken,
    String? oauthTokenType,
    DateTime? oauthExpiresAt,
    bool clearExpiry = false,
  }) {
    return IntegrationSettings(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      metricsPath: metricsPath ?? this.metricsPath,
      apiKey: apiKey ?? this.apiKey,
      oauthEnabled: oauthEnabled ?? this.oauthEnabled,
      oauthClientId: oauthClientId ?? this.oauthClientId,
      oauthScope: oauthScope ?? this.oauthScope,
      oauthDeviceEndpoint: oauthDeviceEndpoint ?? this.oauthDeviceEndpoint,
      oauthTokenEndpoint: oauthTokenEndpoint ?? this.oauthTokenEndpoint,
      oauthAccessToken: oauthAccessToken ?? this.oauthAccessToken,
      oauthTokenType: oauthTokenType ?? this.oauthTokenType,
      oauthExpiresAt: clearExpiry ? null : oauthExpiresAt ?? this.oauthExpiresAt,
    );
  }
}

class IntegrationSettingsNotifier extends StateNotifier<IntegrationSettings> {
  static const _enabledKey = 'integration_enabled';
  static const _baseUrlKey = 'integration_base_url';
  static const _metricsPathKey = 'integration_metrics_path';
  static const _apiKeyKey = 'integration_api_key';
  static const _oauthEnabledKey = 'integration_oauth_enabled';
  static const _oauthClientIdKey = 'integration_oauth_client_id';
  static const _oauthScopeKey = 'integration_oauth_scope';
  static const _oauthDeviceEndpointKey = 'integration_oauth_device_endpoint';
  static const _oauthTokenEndpointKey = 'integration_oauth_token_endpoint';
  static const _oauthAccessTokenKey = 'integration_oauth_access_token';
  static const _oauthTokenTypeKey = 'integration_oauth_token_type';
  static const _oauthExpiresAtKey = 'integration_oauth_expires_at';

  IntegrationSettingsNotifier()
      : super(
          const IntegrationSettings(
            enabled: false,
            baseUrl: '',
            metricsPath: '/api/metrics',
            apiKey: '',
            oauthEnabled: false,
            oauthClientId: '',
            oauthScope: '',
            oauthDeviceEndpoint: '',
            oauthTokenEndpoint: '',
            oauthAccessToken: '',
            oauthTokenType: 'Bearer',
            oauthExpiresAt: null,
          ),
        ) {
    load();
  }

  Future<IntegrationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawExpiresAt = prefs.getInt(_oauthExpiresAtKey);
    final nextState = state.copyWith(
      enabled: prefs.getBool(_enabledKey) ?? state.enabled,
      baseUrl: prefs.getString(_baseUrlKey) ?? state.baseUrl,
      metricsPath: prefs.getString(_metricsPathKey) ?? state.metricsPath,
      apiKey: prefs.getString(_apiKeyKey) ?? state.apiKey,
      oauthEnabled: prefs.getBool(_oauthEnabledKey) ?? state.oauthEnabled,
      oauthClientId: prefs.getString(_oauthClientIdKey) ?? state.oauthClientId,
      oauthScope: prefs.getString(_oauthScopeKey) ?? state.oauthScope,
      oauthDeviceEndpoint:
          prefs.getString(_oauthDeviceEndpointKey) ?? state.oauthDeviceEndpoint,
      oauthTokenEndpoint:
          prefs.getString(_oauthTokenEndpointKey) ?? state.oauthTokenEndpoint,
      oauthAccessToken:
          prefs.getString(_oauthAccessTokenKey) ?? state.oauthAccessToken,
      oauthTokenType:
          prefs.getString(_oauthTokenTypeKey) ?? state.oauthTokenType,
      oauthExpiresAt: rawExpiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rawExpiresAt),
      clearExpiry: rawExpiresAt == null,
    );
    if (mounted) {
      state = nextState;
    }
    return nextState;
  }

  Future<void> update({
    required bool enabled,
    required String baseUrl,
    required String metricsPath,
    required String apiKey,
    required bool oauthEnabled,
    required String oauthClientId,
    required String oauthScope,
    required String oauthDeviceEndpoint,
    required String oauthTokenEndpoint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nextState = state.copyWith(
      enabled: enabled,
      baseUrl: baseUrl.trim(),
      metricsPath: metricsPath.trim().isEmpty ? '/api/metrics' : metricsPath.trim(),
      apiKey: apiKey.trim(),
      oauthEnabled: oauthEnabled,
      oauthClientId: oauthClientId.trim(),
      oauthScope: oauthScope.trim(),
      oauthDeviceEndpoint: oauthDeviceEndpoint.trim(),
      oauthTokenEndpoint: oauthTokenEndpoint.trim(),
    );
    await prefs.setBool(_enabledKey, nextState.enabled);
    await prefs.setString(_baseUrlKey, nextState.baseUrl);
    await prefs.setString(_metricsPathKey, nextState.metricsPath);
    await prefs.setString(_apiKeyKey, nextState.apiKey);
    await prefs.setBool(_oauthEnabledKey, nextState.oauthEnabled);
    await prefs.setString(_oauthClientIdKey, nextState.oauthClientId);
    await prefs.setString(_oauthScopeKey, nextState.oauthScope);
    await prefs.setString(_oauthDeviceEndpointKey, nextState.oauthDeviceEndpoint);
    await prefs.setString(_oauthTokenEndpointKey, nextState.oauthTokenEndpoint);
    state = nextState;
  }

  Future<void> saveOAuthToken({
    required String accessToken,
    required String tokenType,
    DateTime? expiresAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_oauthAccessTokenKey, accessToken);
    await prefs.setString(_oauthTokenTypeKey, tokenType);
    if (expiresAt != null) {
      await prefs.setInt(_oauthExpiresAtKey, expiresAt.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_oauthExpiresAtKey);
    }
    state = state.copyWith(
      oauthAccessToken: accessToken,
      oauthTokenType: tokenType,
      oauthExpiresAt: expiresAt,
      clearExpiry: expiresAt == null,
    );
  }

  Future<void> clearOAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_oauthAccessTokenKey);
    await prefs.remove(_oauthTokenTypeKey);
    await prefs.remove(_oauthExpiresAtKey);
    state = state.copyWith(
      oauthAccessToken: '',
      oauthTokenType: 'Bearer',
      clearExpiry: true,
    );
  }
}

final integrationSettingsProvider =
    StateNotifierProvider<IntegrationSettingsNotifier, IntegrationSettings>(
  (ref) => IntegrationSettingsNotifier(),
);