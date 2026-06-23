import 'dart:math' as math;

import '../../data/metric_model.dart';

/// Retorna os valores de uma grandeza na mesma ordem de [metrics].
///
/// As energias aparente e reativa são integradas a partir das potências
/// instantâneas. A lista deve estar em ordem cronológica crescente.
List<double> chartValuesForField(List<Metric> metrics, String field) {
  switch (field) {
    case 'energy':
    case 'energy_active':
      return [for (final metric in metrics) metric.energy];
    case 'energy_apparent':
      return _integrateEnergy(metrics, _apparentPower);
    case 'energy_reactive':
      return _integrateEnergy(metrics, _reactivePower);
    default:
      return [for (final metric in metrics) metricValueForField(metric, field)];
  }
}

double metricValueForField(Metric metric, String field) {
  switch (field) {
    case 'voltage':
      return metric.voltage;
    case 'current':
      return metric.current;
    case 'power':
    case 'power_active':
      return metric.power;
    case 'power_apparent':
      return _apparentPower(metric);
    case 'power_reactive':
      return _reactivePower(metric);
    case 'pf':
      return metric.pf;
    case 'frequency':
      return metric.frequency;
    case 'energy':
    case 'energy_active':
      return metric.energy;
    case 'temperature':
      return metric.temperature ?? 0;
    default:
      return 0;
  }
}

double _apparentPower(Metric metric) => metric.voltage * metric.current;

double _reactivePower(Metric metric) {
  final apparentPower = _apparentPower(metric);
  return math.sqrt(
    math.max(
      (apparentPower * apparentPower) - (metric.power * metric.power),
      0.0,
    ),
  );
}

List<double> _integrateEnergy(
  List<Metric> metrics,
  double Function(Metric metric) power,
) {
  if (metrics.isEmpty) {
    return const [];
  }

  const millisecondsPerKilounitHour = 3600000000.0;
  var accumulatedEnergy = 0.0;
  final values = <double>[0];

  for (var index = 1; index < metrics.length; index++) {
    final previous = metrics[index - 1];
    final current = metrics[index];
    final elapsedMs = current.timestamp
        .difference(previous.timestamp)
        .inMilliseconds;

    if (elapsedMs > 0) {
      final averagePower = (power(previous) + power(current)) / 2;
      accumulatedEnergy +=
          averagePower * elapsedMs / millisecondsPerKilounitHour;
    }
    values.add(accumulatedEnergy);
  }

  return values;
}
