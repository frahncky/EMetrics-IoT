import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'metric_provider.dart';
import 'mqtt_stream_provider.dart';
import 'mqtt_metric_parser.dart';
import '../services/background_mqtt_service.dart';

typedef BackgroundRunningCheck = Future<bool> Function();

final backgroundRunningCheckProvider = Provider<BackgroundRunningCheck>((ref) {
  return BackgroundMqttService.isRunning;
});

final mqttMetricSaverProvider = Provider<void>((ref) {
  final streamAsync = ref.watch(mqttStreamProvider);
  streamAsync.whenData((messages) async {
    final isBackgroundActive = await ref.read(backgroundRunningCheckProvider)();
    if (isBackgroundActive) {
      return;
    }

    if (messages.isNotEmpty) {
      final last = messages.last;
      final payload = (last.payload as MqttPublishMessage).payload.message;
      final payloadString = String.fromCharCodes(payload);
      final metric = parseMetricFromMqtt(payloadString);
      if (metric != null) {
        final repo = ref.read(metricRepositoryProvider);
        await repo.insertMetric(metric);
        ref.invalidate(metricsProvider);
        ref.invalidate(metricsByRangeProvider);
      }
    }
  });
});
