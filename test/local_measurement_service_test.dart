import 'package:e_metrics_iot/src/services/local_measurement_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalMeasurementService', () {
    test('buildMetricsUri cria endpoint padrão com host cru', () {
      final uri = LocalMeasurementService.buildMetricsUri('192.168.4.1');

      expect(uri.toString(), 'http://192.168.4.1/metrics');
    });

    test('buildMetricsUri preserva schema e porta existentes', () {
      final uri = LocalMeasurementService.buildMetricsUri(
        'http://10.0.0.55:8080',
      );

      expect(uri.toString(), 'http://10.0.0.55:8080/metrics');
    });

    test('buildMetricsUri lança erro para host inválido', () {
      expect(
        () => LocalMeasurementService.buildMetricsUri('  '),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
