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
      oauthExpiresAt: clearExpiry
          ? null
          : oauthExpiresAt ?? this.oauthExpiresAt,
    );
  }
}

const defaultIntegrationSettings = IntegrationSettings(
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
);

Future<IntegrationSettings> loadIntegrationSettings() async {
  const defaults = defaultIntegrationSettings;
  final prefs = await SharedPreferences.getInstance();
  final rawExpiresAt = prefs.getInt(
    IntegrationSettingsNotifier.oauthExpiresAtKey,
  );
  return IntegrationSettings(
    enabled:
        prefs.getBool(IntegrationSettingsNotifier.enabledKey) ??
        defaults.enabled,
    baseUrl:
        prefs.getString(IntegrationSettingsNotifier.baseUrlKey) ??
        defaults.baseUrl,
    metricsPath:
        prefs.getString(IntegrationSettingsNotifier.metricsPathKey) ??
        defaults.metricsPath,
    apiKey:
        prefs.getString(IntegrationSettingsNotifier.apiKeyKey) ??
        defaults.apiKey,
    oauthEnabled:
        prefs.getBool(IntegrationSettingsNotifier.oauthEnabledKey) ??
        defaults.oauthEnabled,
    oauthClientId:
        prefs.getString(IntegrationSettingsNotifier.oauthClientIdKey) ??
        defaults.oauthClientId,
    oauthScope:
        prefs.getString(IntegrationSettingsNotifier.oauthScopeKey) ??
        defaults.oauthScope,
    oauthDeviceEndpoint:
        prefs.getString(IntegrationSettingsNotifier.oauthDeviceEndpointKey) ??
        defaults.oauthDeviceEndpoint,
    oauthTokenEndpoint:
        prefs.getString(IntegrationSettingsNotifier.oauthTokenEndpointKey) ??
        defaults.oauthTokenEndpoint,
    oauthAccessToken:
        prefs.getString(IntegrationSettingsNotifier.oauthAccessTokenKey) ??
        defaults.oauthAccessToken,
    oauthTokenType:
        prefs.getString(IntegrationSettingsNotifier.oauthTokenTypeKey) ??
        defaults.oauthTokenType,
    oauthExpiresAt: rawExpiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(rawExpiresAt),
  );
}

class IntegrationSettingsNotifier extends StateNotifier<IntegrationSettings> {
  static const enabledKey = 'integration_enabled';
  static const baseUrlKey = 'integration_base_url';
  static const metricsPathKey = 'integration_metrics_path';
  static const apiKeyKey = 'integration_api_key';
  static const oauthEnabledKey = 'integration_oauth_enabled';
  static const oauthClientIdKey = 'integration_oauth_client_id';
  static const oauthScopeKey = 'integration_oauth_scope';
  static const oauthDeviceEndpointKey = 'integration_oauth_device_endpoint';
  static const oauthTokenEndpointKey = 'integration_oauth_token_endpoint';
  static const oauthAccessTokenKey = 'integration_oauth_access_token';
  static const oauthTokenTypeKey = 'integration_oauth_token_type';
  static const oauthExpiresAtKey = 'integration_oauth_expires_at';
  var _revision = 0;

  IntegrationSettingsNotifier() : super(defaultIntegrationSettings) {
    load();
  }

  Future<IntegrationSettings> load() async {
    final loadRevision = _revision;
    final nextState = await loadIntegrationSettings();
    if (mounted && loadRevision == _revision) {
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
    _revision++;
    final prefs = await SharedPreferences.getInstance();
    final nextState = state.copyWith(
      enabled: enabled,
      baseUrl: baseUrl.trim(),
      metricsPath: metricsPath.trim().isEmpty
          ? '/api/metrics'
          : metricsPath.trim(),
      apiKey: apiKey.trim(),
      oauthEnabled: oauthEnabled,
      oauthClientId: oauthClientId.trim(),
      oauthScope: oauthScope.trim(),
      oauthDeviceEndpoint: oauthDeviceEndpoint.trim(),
      oauthTokenEndpoint: oauthTokenEndpoint.trim(),
    );
    await prefs.setBool(enabledKey, nextState.enabled);
    await prefs.setString(baseUrlKey, nextState.baseUrl);
    await prefs.setString(metricsPathKey, nextState.metricsPath);
    await prefs.setString(apiKeyKey, nextState.apiKey);
    await prefs.setBool(oauthEnabledKey, nextState.oauthEnabled);
    await prefs.setString(oauthClientIdKey, nextState.oauthClientId);
    await prefs.setString(oauthScopeKey, nextState.oauthScope);
    await prefs.setString(
      oauthDeviceEndpointKey,
      nextState.oauthDeviceEndpoint,
    );
    await prefs.setString(oauthTokenEndpointKey, nextState.oauthTokenEndpoint);
    state = nextState;
  }

  Future<void> saveOAuthToken({
    required String accessToken,
    required String tokenType,
    DateTime? expiresAt,
  }) async {
    _revision++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(oauthAccessTokenKey, accessToken);
    await prefs.setString(oauthTokenTypeKey, tokenType);
    if (expiresAt != null) {
      await prefs.setInt(oauthExpiresAtKey, expiresAt.millisecondsSinceEpoch);
    } else {
      await prefs.remove(oauthExpiresAtKey);
    }
    state = state.copyWith(
      oauthAccessToken: accessToken,
      oauthTokenType: tokenType,
      oauthExpiresAt: expiresAt,
      clearExpiry: expiresAt == null,
    );
  }

  Future<void> clearOAuthToken() async {
    _revision++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(oauthAccessTokenKey);
    await prefs.remove(oauthTokenTypeKey);
    await prefs.remove(oauthExpiresAtKey);
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
