import 'dart:async';
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

/// Serializes MQTT metric writes and debounces invalidations to prevent
/// race conditions and excessive provider recomputes during high-frequency
/// message ingestion.
final mqttMetricSaverProvider = Provider<void>((ref) {
  Future<void> lastOperation = Future.value();
  Timer? debounceTimer;
  
  ref.watch(mqttStreamProvider).whenData((messages) async {
    final isBackgroundActive = await ref.read(backgroundRunningCheckProvider)();
    if (isBackgroundActive || messages.isEmpty) {
      return;
    }

    // Serialize writes: chain operations to prevent concurrent DB writes
    lastOperation = lastOperation.then((_) async {
      final last = messages.last;
      final payload = (last.payload as MqttPublishMessage).payload.message;
      final payloadString = String.fromCharCodes(payload);
      final metric = parseMetricFromMqtt(payloadString);
      if (metric != null) {
        final repo = ref.read(metricRepositoryProvider);
        await repo.insertMetric(metric);
        
        // Debounce invalidations: batch provider updates during high message rate
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 100), () {
          ref.invalidate(metricsProvider);
          ref.invalidate(metricsByRangeProvider);
        });
      }
    });
  });
});
