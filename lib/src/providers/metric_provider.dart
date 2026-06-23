import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../data/metric_model.dart';
import '../data/metric_repository.dart';
import 'mqtt_stream_provider.dart';
import 'mqtt_metric_parser.dart';

class MetricsRangeQuery {
  final int? from;
  final int? to;

  const MetricsRangeQuery({this.from, this.to});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MetricsRangeQuery && other.from == from && other.to == to;
  }

  @override
  int get hashCode => Object.hash(from, to);
}

final metricRepositoryProvider = Provider((ref) => MetricRepository());

final metricsProvider = FutureProvider<List<Metric>>((ref) async {
  final repo = ref.watch(metricRepositoryProvider);
  return repo.getMetrics();
});

final metricsByRangeProvider =
    FutureProvider.family<List<Metric>, MetricsRangeQuery>((ref, query) async {
  final repo = ref.watch(metricRepositoryProvider);
  return repo.getMetrics(from: query.from, to: query.to);
});

/// Última métrica recebida diretamente do stream MQTT, sem passar pelo banco.
/// Atualiza imediatamente quando uma mensagem chega, sem debounce.
final latestMqttMetricProvider = Provider<Metric?>((ref) {
  return ref.watch(mqttStreamProvider).whenOrNull(data: (messages) {
    if (messages.isEmpty) return null;
    final payload =
        (messages.last.payload as MqttPublishMessage).payload.message;
    return parseMetricFromMqtt(String.fromCharCodes(payload));
  });
});
