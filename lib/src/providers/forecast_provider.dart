import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/metric_model.dart';
import 'metric_provider.dart';

class ForecastSnapshot {
  final double projectedPowerWatts;
  final double projectedEnergyKwh;
  final double powerSlopePerMinute;
  final int sampleCount;

  const ForecastSnapshot({
    required this.projectedPowerWatts,
    required this.projectedEnergyKwh,
    required this.powerSlopePerMinute,
    required this.sampleCount,
  });

  String get trendLabel {
    if (powerSlopePerMinute > 0.15) {
      return 'Tendência de alta';
    }
    if (powerSlopePerMinute < -0.15) {
      return 'Tendência de queda';
    }
    return 'Tendência estável';
  }
}

final forecastProvider = Provider<AsyncValue<ForecastSnapshot?>>((ref) {
  final metricsAsync = ref.watch(metricsProvider);
  return metricsAsync.whenData(buildForecastForMetrics);
});

ForecastSnapshot? buildForecastForMetrics(List<Metric> metrics) {
  final recent = metrics.take(24).toList().reversed.toList();
  if (recent.length < 3) {
    return null;
  }

  final firstTimestamp = recent.first.timestamp;
  final x = <double>[];
  final y = <double>[];
  for (final metric in recent) {
    x.add(metric.timestamp.difference(firstTimestamp).inSeconds / 60.0);
    y.add(metric.power);
  }

  final slope = _linearRegressionSlope(x, y);
  final averagePower = y.reduce((left, right) => left + right) / y.length;
  final lastMetric = recent.last;
  final projectedPower = math.max(lastMetric.power + (slope * 30), 0).toDouble();
  final projectedEnergy = lastMetric.energy + ((averagePower / 1000) * 1);

  return ForecastSnapshot(
    projectedPowerWatts: projectedPower,
    projectedEnergyKwh: projectedEnergy,
    powerSlopePerMinute: slope,
    sampleCount: recent.length,
  );
}

double _linearRegressionSlope(List<double> x, List<double> y) {
  if (x.length != y.length || x.length < 2) {
    return 0;
  }
  final count = x.length.toDouble();
  final sumX = x.reduce((left, right) => left + right);
  final sumY = y.reduce((left, right) => left + right);
  final sumXY = Iterable<int>.generate(x.length)
      .map((index) => x[index] * y[index])
      .reduce((left, right) => left + right);
  final sumXX = x.map((value) => value * value).reduce((left, right) => left + right);
  final denominator = (count * sumXX) - (sumX * sumX);
  if (denominator == 0) {
    return 0;
  }
  return ((count * sumXY) - (sumX * sumY)) / denominator;
}