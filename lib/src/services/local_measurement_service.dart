import 'package:http/http.dart' as http;

class LocalMeasurementService {
  const LocalMeasurementService();

  static Uri buildMetricsUri(String hostOrUrl, {int port = 80}) {
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
      path: '/metrics',
    );
  }

  Future<String> fetchMetricsPayload({
    required String espHost,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final uri = buildMetricsUri(espHost);
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Falha ao obter métricas locais (HTTP ${response.statusCode}).',
      );
    }
    return response.body;
  }
}
