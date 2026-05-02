import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/ui/history/history_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildHistoryPdfBytes gera conteúdo PDF para métricas históricas', () async {
    final bytes = await buildHistoryPdfBytes([
      Metric(
        timestamp: DateTime(2026, 5, 1, 8, 0),
        voltage: 220,
        current: 5.1,
        power: 1122,
        pf: 0.98,
        frequency: 60,
        energy: 15.2,
      ),
      Metric(
        timestamp: DateTime(2026, 5, 1, 9, 0),
        voltage: 221,
        current: 5.4,
        power: 1193,
        pf: 0.99,
        frequency: 60,
        energy: 15.9,
      ),
    ]);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}