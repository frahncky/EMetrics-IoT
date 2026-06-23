import 'dart:convert';

import 'package:http/http.dart' as http;

class EspProvisioningResult {
  final bool ok;
  final String message;

  const EspProvisioningResult({required this.ok, required this.message});
}

class EspWifiNetwork {
  final String ssid;
  final bool active;
  final int priority;

  const EspWifiNetwork({
    required this.ssid,
    required this.active,
    required this.priority,
  });

  factory EspWifiNetwork.fromJson(Map<String, dynamic> json) {
    return EspWifiNetwork(
      ssid: (json['ssid'] as String? ?? '').trim(),
      active: json['active'] == true,
      priority: json['priority'] is int && (json['priority'] as int) > 0
          ? json['priority'] as int
          : 1,
    );
  }
}

class EspWifiConnectionSettings {
  static const minDelaySeconds = 5;
  static const maxDelaySeconds = 600;
  static const defaultInitialConnectTimeoutSeconds = 20;
  static const defaultRetryIntervalSeconds = 15;
  static const defaultFallbackApDelaySeconds = 60;

  final int initialConnectTimeoutSeconds;
  final int retryIntervalSeconds;
  final int fallbackApDelaySeconds;

  const EspWifiConnectionSettings({
    required this.initialConnectTimeoutSeconds,
    required this.retryIntervalSeconds,
    required this.fallbackApDelaySeconds,
  });

  const EspWifiConnectionSettings.defaults()
    : initialConnectTimeoutSeconds = defaultInitialConnectTimeoutSeconds,
      retryIntervalSeconds = defaultRetryIntervalSeconds,
      fallbackApDelaySeconds = defaultFallbackApDelaySeconds;

  factory EspWifiConnectionSettings.fromJson(Map<String, dynamic> json) {
    int valueFor(String key, int fallback) {
      final value = json[key];
      if (value is int &&
          value >= minDelaySeconds &&
          value <= maxDelaySeconds) {
        return value;
      }
      return fallback;
    }

    return EspWifiConnectionSettings(
      initialConnectTimeoutSeconds: valueFor(
        'initialConnectTimeoutSeconds',
        defaultInitialConnectTimeoutSeconds,
      ),
      retryIntervalSeconds: valueFor(
        'retryIntervalSeconds',
        defaultRetryIntervalSeconds,
      ),
      fallbackApDelaySeconds: valueFor(
        'fallbackApDelaySeconds',
        defaultFallbackApDelaySeconds,
      ),
    );
  }
}

class WifiScanResult {
  final String ssid;
  final int rssi;
  final bool open;
  final String authLabel;

  const WifiScanResult({
    required this.ssid,
    required this.rssi,
    required this.open,
    required this.authLabel,
  });

  factory WifiScanResult.fromJson(Map<String, dynamic> json) {
    return WifiScanResult(
      ssid: (json['ssid'] as String? ?? '').trim(),
      rssi: (json['rssi'] as int? ?? -100),
      open: json['open'] == true,
      authLabel: (json['authLabel'] as String? ?? 'WPA2').trim(),
    );
  }
}

class WifiConnectionStatus {
  final bool connected;
  final int statusCode;
  final String description;
  final String ssid;
  final bool enterprise;
  final String? ip;
  final int? rssi;

  const WifiConnectionStatus({
    required this.connected,
    required this.statusCode,
    required this.description,
    required this.ssid,
    required this.enterprise,
    this.ip,
    this.rssi,
  });

  factory WifiConnectionStatus.fromJson(Map<String, dynamic> json) {
    return WifiConnectionStatus(
      connected: json['connected'] == true,
      statusCode: (json['status'] as int? ?? -1),
      description: (json['description'] as String? ?? '').trim(),
      ssid: (json['ssid'] as String? ?? '').trim(),
      enterprise: json['enterprise'] == true,
      ip: json['ip'] as String?,
      rssi: json['rssi'] as int?,
    );
  }
}

class EspProvisioningService {
  const EspProvisioningService();

  static const int mqttClientIdMaxLength = 50;
  static const String defaultEspClientId = 'esp32_pzem_001';
  static const String _espClientIdSuffix = '_esp32';

  static String buildDefaultEspClientId(String appClientId) {
    final normalized = appClientId.trim().replaceAll(RegExp(r'\s+'), '_');
    if (normalized.isEmpty) {
      return defaultEspClientId;
    }

    final maxBaseLength = mqttClientIdMaxLength - _espClientIdSuffix.length;
    final base = normalized.length > maxBaseLength
        ? normalized.substring(0, maxBaseLength)
        : normalized;
    return '$base$_espClientIdSuffix';
  }

  static Uri buildUri(String hostOrUrl, {String path = '/', int port = 80}) {
    final raw = hostOrUrl.trim();
    if (raw.isEmpty) {
      throw const FormatException('Informe o IP ou URL do ESP32.');
    }

    final candidate = raw.contains('://') ? raw : 'http://$raw';
    final parsed = Uri.tryParse(candidate);
    if (parsed == null || parsed.host.isEmpty) {
      throw const FormatException('IP ou URL do ESP32 inválido.');
    }

    return Uri(
      scheme: parsed.scheme.isEmpty ? 'http' : parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : port,
      path: path,
    );
  }

  static Uri buildProvisioningUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/provision', port: port);
  }

  static Uri buildWifiNetworksUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-networks', port: port);
  }

  static Uri buildWifiNetworkDeleteUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-networks/delete', port: port);
  }

  static Uri buildWifiNetworkReorderUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-networks/reorder', port: port);
  }

  static Uri buildWifiConnectionSettingsUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-connection-settings', port: port);
  }

  static Uri buildFirmwareUpdateUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/firmware/update', port: port);
  }

  static Uri buildWifiScanUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-scan', port: port);
  }

  static Uri buildResetEnergyUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/reset-energy', port: port);
  }

  static Uri buildWifiStatusUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-status', port: port);
  }

  static Uri buildWifiReconnectUri(String hostOrUrl, {int port = 80}) {
    return buildUri(hostOrUrl, path: '/wifi-reconnect', port: port);
  }

  static Map<String, String> buildFormData({
    required String wifiSsid,
    required String wifiUsername,
    required String wifiPassword,
    required String mqttHost,
    required int mqttPort,
    required String mqttUser,
    required String mqttPassword,
    required String mqttTopic,
    required String mqttRequestTopic,
    required String mqttClientId,
    required bool useTls,
    int initialConnectTimeoutSeconds =
        EspWifiConnectionSettings.defaultInitialConnectTimeoutSeconds,
    int retryIntervalSeconds =
        EspWifiConnectionSettings.defaultRetryIntervalSeconds,
    int fallbackApDelaySeconds =
        EspWifiConnectionSettings.defaultFallbackApDelaySeconds,
    String otaPassword = '',
  }) {
    return {
      'ssid': wifiSsid.trim(),
      'wifiUsername': wifiUsername.trim(),
      'wifiPassword': wifiPassword,
      'mqttHost': mqttHost.trim(),
      'mqttPort': '$mqttPort',
      'mqttUser': mqttUser.trim(),
      'mqttPassword': mqttPassword,
      'mqttTopic': mqttTopic.trim(),
      'mqttRequestTopic': mqttRequestTopic.trim(),
      'clientId': mqttClientId.trim(),
      'useTls': useTls ? '1' : '0',
      'initialConnectTimeoutSeconds': '$initialConnectTimeoutSeconds',
      'retryIntervalSeconds': '$retryIntervalSeconds',
      'fallbackApDelaySeconds': '$fallbackApDelaySeconds',
      if (otaPassword.trim().isNotEmpty) 'otaPassword': otaPassword,
    };
  }

  static Map<String, String> buildWifiNetworkFormData({
    required String ssid,
    required String wifiUsername,
    required String wifiPassword,
    String? oldSsid,
    bool keepUsername = false,
    bool keepPassword = false,
  }) {
    return {
      'ssid': ssid.trim(),
      'wifiUsername': wifiUsername.trim(),
      'wifiPassword': wifiPassword,
      if (oldSsid != null && oldSsid.trim().isNotEmpty)
        'oldSsid': oldSsid.trim(),
      'keepUsername': keepUsername ? '1' : '0',
      'keepPassword': keepPassword ? '1' : '0',
    };
  }

  static Map<String, String> buildWifiConnectionSettingsFormData({
    required int initialConnectTimeoutSeconds,
    required int retryIntervalSeconds,
    required int fallbackApDelaySeconds,
  }) {
    return {
      'initialConnectTimeoutSeconds': '$initialConnectTimeoutSeconds',
      'retryIntervalSeconds': '$retryIntervalSeconds',
      'fallbackApDelaySeconds': '$fallbackApDelaySeconds',
    };
  }

  static List<EspWifiNetwork> parseWifiNetworks(String rawBody) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    final networks = decoded['networks'];
    if (networks is! List) {
      return const [];
    }
    return networks
        .whereType<Map<String, dynamic>>()
        .map(EspWifiNetwork.fromJson)
        .where((network) => network.ssid.isNotEmpty)
        .toList();
  }

  static EspWifiConnectionSettings parseWifiConnectionSettings(String rawBody) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta inválida das configurações Wi-Fi.');
    }
    return EspWifiConnectionSettings.fromJson(decoded);
  }

  Future<EspProvisioningResult> provision({
    required String espHost,
    required String wifiSsid,
    required String wifiUsername,
    required String wifiPassword,
    required String mqttHost,
    required int mqttPort,
    required String mqttUser,
    required String mqttPassword,
    required String mqttTopic,
    required String mqttRequestTopic,
    required String mqttClientId,
    required bool useTls,
    int initialConnectTimeoutSeconds =
        EspWifiConnectionSettings.defaultInitialConnectTimeoutSeconds,
    int retryIntervalSeconds =
        EspWifiConnectionSettings.defaultRetryIntervalSeconds,
    int fallbackApDelaySeconds =
        EspWifiConnectionSettings.defaultFallbackApDelaySeconds,
    String otaPassword = '',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = buildProvisioningUri(espHost);
    final body = buildFormData(
      wifiSsid: wifiSsid,
      wifiUsername: wifiUsername,
      wifiPassword: wifiPassword,
      mqttHost: mqttHost,
      mqttPort: mqttPort,
      mqttUser: mqttUser,
      mqttPassword: mqttPassword,
      mqttTopic: mqttTopic,
      mqttRequestTopic: mqttRequestTopic,
      mqttClientId: mqttClientId,
      useTls: useTls,
      initialConnectTimeoutSeconds: initialConnectTimeoutSeconds,
      retryIntervalSeconds: retryIntervalSeconds,
      fallbackApDelaySeconds: fallbackApDelaySeconds,
      otaPassword: otaPassword,
    );

    try {
      final response = await http.post(uri, body: body).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final message =
            _extractMessage(response.body) ??
            'Configuração enviada com sucesso. O ESP32 vai reiniciar.';
        return EspProvisioningResult(ok: true, message: message);
      }

      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha no provisionamento (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message:
            'Não foi possível conectar ao ESP32. Verifique se o celular está na rede/AP do dispositivo.',
      );
    }
  }

  Future<List<EspWifiNetwork>> loadWifiNetworks({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiNetworksUri(espHost);
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractMessage(response.body) ??
            'Falha ao carregar redes salvas (HTTP ${response.statusCode}).',
      );
    }
    return parseWifiNetworks(response.body);
  }

  Future<EspWifiConnectionSettings> loadWifiConnectionSettings({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiConnectionSettingsUri(espHost);
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractMessage(response.body) ??
            'Falha ao carregar tempos de conexão Wi-Fi (HTTP ${response.statusCode}).',
      );
    }
    return parseWifiConnectionSettings(response.body);
  }

  Future<EspProvisioningResult> saveWifiNetwork({
    required String espHost,
    required String ssid,
    required String wifiUsername,
    required String wifiPassword,
    String? oldSsid,
    bool keepUsername = false,
    bool keepPassword = false,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiNetworksUri(espHost);
    final body = buildWifiNetworkFormData(
      ssid: ssid,
      wifiUsername: wifiUsername,
      wifiPassword: wifiPassword,
      oldSsid: oldSsid,
      keepUsername: keepUsername,
      keepPassword: keepPassword,
    );

    try {
      final response = await http.post(uri, body: body).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message:
              _extractMessage(response.body) ?? 'Rede Wi-Fi salva no ESP32.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao salvar rede Wi-Fi (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message: 'Não foi possível conectar ao ESP32 para salvar a rede Wi-Fi.',
      );
    }
  }

  Future<EspProvisioningResult> deleteWifiNetwork({
    required String espHost,
    required String ssid,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiNetworkDeleteUri(espHost);

    try {
      final response = await http
          .post(uri, body: {'ssid': ssid.trim()})
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message:
              _extractMessage(response.body) ?? 'Rede Wi-Fi excluída do ESP32.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao excluir rede Wi-Fi (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message:
            'Não foi possível conectar ao ESP32 para excluir a rede Wi-Fi.',
      );
    }
  }

  Future<EspProvisioningResult> moveWifiNetwork({
    required String espHost,
    required String ssid,
    required bool moveUp,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiNetworkReorderUri(espHost);

    try {
      final response = await http
          .post(
            uri,
            body: {'ssid': ssid.trim(), 'direction': moveUp ? 'up' : 'down'},
          )
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message:
              _extractMessage(response.body) ??
              'Prioridade da rede atualizada no ESP32.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao atualizar prioridade da rede (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message: 'Não foi possível conectar ao ESP32 para reordenar a rede.',
      );
    }
  }

  Future<EspProvisioningResult> saveWifiConnectionSettings({
    required String espHost,
    required int initialConnectTimeoutSeconds,
    required int retryIntervalSeconds,
    required int fallbackApDelaySeconds,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiConnectionSettingsUri(espHost);
    final body = buildWifiConnectionSettingsFormData(
      initialConnectTimeoutSeconds: initialConnectTimeoutSeconds,
      retryIntervalSeconds: retryIntervalSeconds,
      fallbackApDelaySeconds: fallbackApDelaySeconds,
    );

    try {
      final response = await http.post(uri, body: body).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message:
              _extractMessage(response.body) ??
              'Tempos de conexão Wi-Fi salvos no ESP32.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao salvar tempos de conexão Wi-Fi (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message:
            'Não foi possível conectar ao ESP32 para salvar os tempos de conexão Wi-Fi.',
      );
    }
  }

  Future<EspProvisioningResult> uploadFirmware({
    required String espHost,
    required String otaPassword,
    required List<int> firmwareBytes,
    required String fileName,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (otaPassword.trim().isEmpty) {
      return const EspProvisioningResult(
        ok: false,
        message: 'Informe a chave OTA definida no provisionamento do ESP32.',
      );
    }
    if (firmwareBytes.isEmpty) {
      return const EspProvisioningResult(
        ok: false,
        message: 'O arquivo de firmware está vazio.',
      );
    }

    final uri = buildFirmwareUpdateUri(espHost);
    final request = http.MultipartRequest('POST', uri)
      ..headers['X-EMetrics-OTA-Key'] = otaPassword
      ..files.add(
        http.MultipartFile.fromBytes(
          'firmware',
          firmwareBytes,
          filename: fileName,
        ),
      );

    try {
      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message:
              _extractMessage(response.body) ??
              'Firmware enviado. O ESP32 será reiniciado.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao atualizar firmware (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message:
            'Não foi possível enviar o firmware ao ESP32. Verifique a rede e tente novamente.',
      );
    }
  }

  Future<List<WifiScanResult>> scanWifiNetworks({
    required String espHost,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = buildWifiScanUri(espHost);
    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Falha ao escanear redes (HTTP ${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final networks = decoded['networks'];
      if (networks is! List) return const [];
      return networks
          .whereType<Map<String, dynamic>>()
          .map(WifiScanResult.fromJson)
          .where((n) => n.ssid.isNotEmpty)
          .toList();
    } catch (e) {
      throw Exception('Não foi possível escanear redes: $e');
    }
  }

  Future<WifiConnectionStatus> getWifiStatus({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiStatusUri(espHost);
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta inválida do ESP32.');
    }
    return WifiConnectionStatus.fromJson(decoded);
  }

  Future<EspProvisioningResult> triggerWifiReconnect({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiReconnectUri(espHost);
    try {
      final response = await http.post(uri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message: _extractMessage(response.body) ?? 'Reconexão iniciada.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao iniciar reconexão (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message: 'Não foi possível conectar ao ESP32.',
      );
    }
  }

  Future<EspProvisioningResult> resetEnergy({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildResetEnergyUri(espHost);
    try {
      final response = await http.post(uri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspProvisioningResult(
          ok: true,
          message: _extractMessage(response.body) ?? 'Energia acumulada zerada.',
        );
      }
      return EspProvisioningResult(
        ok: false,
        message:
            _extractMessage(response.body) ??
            'Falha ao zerar energia (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message: 'Não foi possível conectar ao ESP32 para zerar a energia.',
      );
    }
  }

  String? _extractMessage(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic> && decoded['message'] is String) {
        return (decoded['message'] as String).trim();
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
