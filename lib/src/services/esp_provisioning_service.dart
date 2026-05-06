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

  const EspWifiNetwork({required this.ssid, required this.active});

  factory EspWifiNetwork.fromJson(Map<String, dynamic> json) {
    return EspWifiNetwork(
      ssid: (json['ssid'] as String? ?? '').trim(),
      active: json['active'] == true,
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

  static Map<String, String> buildFormData({
    required String wifiSsid,
    required String wifiPassword,
    required String mqttHost,
    required int mqttPort,
    required String mqttUser,
    required String mqttPassword,
    required String mqttTopic,
    required String mqttRequestTopic,
    required String mqttClientId,
    required bool useTls,
  }) {
    return {
      'ssid': wifiSsid.trim(),
      'wifiPassword': wifiPassword,
      'mqttHost': mqttHost.trim(),
      'mqttPort': '$mqttPort',
      'mqttUser': mqttUser.trim(),
      'mqttPassword': mqttPassword,
      'mqttTopic': mqttTopic.trim(),
      'mqttRequestTopic': mqttRequestTopic.trim(),
      'clientId': mqttClientId.trim(),
      'useTls': useTls ? '1' : '0',
    };
  }

  static Map<String, String> buildWifiNetworkFormData({
    required String ssid,
    required String wifiPassword,
    String? oldSsid,
    bool keepPassword = false,
  }) {
    return {
      'ssid': ssid.trim(),
      'wifiPassword': wifiPassword,
      if (oldSsid != null && oldSsid.trim().isNotEmpty)
        'oldSsid': oldSsid.trim(),
      'keepPassword': keepPassword ? '1' : '0',
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

  Future<EspProvisioningResult> provision({
    required String espHost,
    required String wifiSsid,
    required String wifiPassword,
    required String mqttHost,
    required int mqttPort,
    required String mqttUser,
    required String mqttPassword,
    required String mqttTopic,
    required String mqttRequestTopic,
    required String mqttClientId,
    required bool useTls,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = buildProvisioningUri(espHost);
    final body = buildFormData(
      wifiSsid: wifiSsid,
      wifiPassword: wifiPassword,
      mqttHost: mqttHost,
      mqttPort: mqttPort,
      mqttUser: mqttUser,
      mqttPassword: mqttPassword,
      mqttTopic: mqttTopic,
      mqttRequestTopic: mqttRequestTopic,
      mqttClientId: mqttClientId,
      useTls: useTls,
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

  Future<EspProvisioningResult> saveWifiNetwork({
    required String espHost,
    required String ssid,
    required String wifiPassword,
    String? oldSsid,
    bool keepPassword = false,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = buildWifiNetworksUri(espHost);
    final body = buildWifiNetworkFormData(
      ssid: ssid,
      wifiPassword: wifiPassword,
      oldSsid: oldSsid,
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
