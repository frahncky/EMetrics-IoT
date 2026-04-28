import 'dart:convert';
import '../data/metric_model.dart';

Metric? parseMetricFromMqtt(String payload) {
  try {
    // Exemplo de payload: '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,"frequency":60,"energy":1.23}'
    final map = json.decode(payload);
    return Metric(
      timestamp: DateTime.now(),
      voltage: (map['voltage'] as num).toDouble(),
      current: (map['current'] as num).toDouble(),
      power: (map['power'] as num).toDouble(),
      pf: (map['pf'] as num).toDouble(),
      frequency: (map['frequency'] as num).toDouble(),
      energy: (map['energy'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}
