import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'metric_provider.dart';
import 'integration_settings_provider.dart';
import 'mqtt_stream_provider.dart';
import 'mqtt_metric_parser.dart';
import '../services/background_mqtt_service.dart';
import '../services/integration_service.dart';
import 'mqtt_settings_provider.dart';

typedef BackgroundRunningCheck = Future<bool> Function();

final backgroundRunningCheckProvider = Provider<BackgroundRunningCheck>((ref) {
  return BackgroundMqttService.isRunning;
});

final integrationServiceProvider = Provider<IntegrationService>((ref) {
  return IntegrationService(
    repository: ref.watch(metricRepositoryProvider),
    loadSettings: () => ref.read(integrationSettingsProvider.notifier).load(),
  );
});

final integrationAutoSyncProvider = Provider<void>((ref) {
  Timer? timer;

  Future<void> flush() async {
    await ref.read(integrationServiceProvider).flushPendingQueue();
  }

  unawaited(flush());
  timer = Timer.periodic(const Duration(seconds: 45), (_) {
    unawaited(flush());
  });
  ref.onDispose(() => timer?.cancel());
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
        final activeProfile = await ref.read(mqttSettingsProvider.notifier).load();
        await repo.insertMetric(metric);
        await ref
            .read(integrationServiceProvider)
            .submitMetric(metric, profileId: activeProfile.profileId);
        
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
