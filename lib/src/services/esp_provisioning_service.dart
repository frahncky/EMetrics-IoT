import 'dart:convert';

import 'package:http/http.dart' as http;

class EspProvisioningResult {
  final bool ok;
  final String message;

  const EspProvisioningResult({required this.ok, required this.message});
}

class EspProvisioningService {
  const EspProvisioningService();

  static Uri buildProvisioningUri(String hostOrUrl, {int port = 80}) {
    final raw = hostOrUrl.trim();
    if (raw.isEmpty) {
      throw const FormatException('Informe o IP ou URL do ESP32.');
    }

    final candidate = raw.contains('://') ? raw : 'http://$raw';
    final parsed = Uri.tryParse(candidate);
    if (parsed == null || parsed.host.isEmpty) {
      throw const FormatException('IP ou URL do ESP32 invalido.');
    }

    return Uri(
      scheme: parsed.scheme.isEmpty ? 'http' : parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : port,
      path: '/provision',
    );
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
        final message = _extractMessage(response.body) ??
            'Configuracao enviada com sucesso. O ESP32 vai reiniciar.';
        return EspProvisioningResult(ok: true, message: message);
      }

      return EspProvisioningResult(
        ok: false,
        message: _extractMessage(response.body) ??
            'Falha no provisionamento (HTTP ${response.statusCode}).',
      );
    } catch (_) {
      return const EspProvisioningResult(
        ok: false,
        message:
            'Nao foi possivel conectar ao ESP32. Verifique se o celular esta na rede/AP do dispositivo.',
      );
    }
  }

  String? _extractMessage(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is Map<String, dynamic> && decoded['message'] is String) {
      return (decoded['message'] as String).trim();
    }

    return null;
  }
}
