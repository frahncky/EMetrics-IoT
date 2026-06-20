import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/ui/shared/chart_metric_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 1, 1, 12);
  final metrics = [
    Metric(
      timestamp: start,
      voltage: 100,
      current: 2,
      power: 160,
      energy: 3,
      pf: 0.8,
      frequency: 60,
    ),
    Metric(
      timestamp: start.add(const Duration(hours: 1)),
      voltage: 100,
      current: 2,
      power: 160,
      energy: 3.16,
      pf: 0.8,
      frequency: 60,
    ),
  ];

  test('mantém o acumulado do PZEM para energia ativa', () {
    expect(chartValuesForField(metrics, 'energy_active'), [3, 3.16]);
  });

  test('integra as energias aparente e reativa em uma janela cronológica', () {
    expect(chartValuesForField(metrics, 'energy_apparent'), [0, 0.2]);
    expect(chartValuesForField(metrics, 'energy_reactive'), [0, 0.12]);
  });
}
