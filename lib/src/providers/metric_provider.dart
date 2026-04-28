import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metric_model.dart';
import '../data/metric_repository.dart';

final metricRepositoryProvider = Provider((ref) => MetricRepository());

final metricsProvider = FutureProvider<List<Metric>>((ref) async {
  final repo = ref.watch(metricRepositoryProvider);
  return repo.getMetrics();
});
