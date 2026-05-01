import 'package:flutter_test/flutter_test.dart';
import 'package:e_metrics_iot/src/data/metric_model.dart';

void main() {
  group('Metric Model Tests', () {
    test('Metric.fromMap should create instance from map', () {
      final map = {
        'id': 1,
        'voltage': 220.5,
        'current': 5.2,
        'power': 1146.0,
        'energy': 45.6,
        'pf': 0.98,
        'frequency': 60.0,
        'timestamp': DateTime(2024, 5, 1, 12, 30).millisecondsSinceEpoch,
      };

      final metric = Metric.fromMap(map);

      expect(metric.id, 1);
      expect(metric.voltage, 220.5);
      expect(metric.current, 5.2);
      expect(metric.power, 1146.0);
      expect(metric.energy, 45.6);
      expect(metric.pf, 0.98);
      expect(metric.frequency, 60.0);
    });

    test('Metric.toMap should convert instance to map', () {
      final timestamp = DateTime(2024, 5, 1, 12, 30);
      final metric = Metric(
        id: 1,
        voltage: 220.5,
        current: 5.2,
        power: 1146.0,
        energy: 45.6,
        pf: 0.98,
        frequency: 60.0,
        timestamp: timestamp,
      );

      final map = metric.toMap();

      expect(map['voltage'], 220.5);
      expect(map['current'], 5.2);
      expect(map['power'], 1146.0);
      expect(map['energy'], 45.6);
      expect(map['pf'], 0.98);
      expect(map['frequency'], 60.0);
    });

    test('Metric properties should be preserved after round-trip', () {
      final timestamp = DateTime(2024, 5, 1, 12, 30);
      final metric = Metric(
        id: 1,
        voltage: 220.5,
        current: 5.2,
        power: 1146.0,
        energy: 45.6,
        pf: 0.98,
        frequency: 60.0,
        timestamp: timestamp,
      );

      final map = metric.toMap();
      final metric2 = Metric.fromMap(map);

      expect(metric2.id, metric.id);
      expect(metric2.voltage, metric.voltage);
      expect(metric2.current, metric.current);
      expect(metric2.power, metric.power);
    });

    test('Metric with NaN values should handle correctly', () {
      final timestamp = DateTime.now();
      final metric = Metric(
        id: 1,
        voltage: double.nan,
        current: 5.2,
        power: 1146.0,
        energy: 45.6,
        pf: double.nan,
        frequency: 60.0,
        timestamp: timestamp,
      );

      expect(metric.voltage.isNaN, true);
      expect(metric.pf.isNaN, true);
      expect(metric.current.isNaN, false);
    });
  });
}
