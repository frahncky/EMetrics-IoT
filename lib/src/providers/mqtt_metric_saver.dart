import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_stream_provider.dart';
import 'mqtt_metric_parser.dart';
import '../data/metric_repository.dart';

final mqttMetricSaverProvider = Provider<void>((ref) {
  final streamAsync = ref.watch(mqttStreamProvider);
  streamAsync.whenData((messages) async {
    if (messages.isNotEmpty) {
      final last = messages.last;
      final payload = (last.payload as MqttPublishMessage).payload.message;
      final payloadString = String.fromCharCodes(payload);
      final metric = parseMetricFromMqtt(payloadString);
      if (metric != null) {
        final repo = MetricRepository();
        await repo.insertMetric(metric);
      }
    }
  });
});
