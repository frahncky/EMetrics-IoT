import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../services/esp_local_host_store.dart';
import '../services/local_measurement_service.dart';
import 'device_storage_provider.dart';
import 'metric_provider.dart';
import 'mqtt_metric_parser.dart';
import 'mqtt_status_provider.dart';

final espLocalHostStoreProvider = Provider<EspLocalHostStore>(
  (ref) => const EspLocalHostStore(),
);

final localMeasurementServiceProvider = Provider<LocalMeasurementService>(
  (ref) => const LocalMeasurementService(),
);

/// Coleta métricas diretamente do ESP32 na rede local quando o MQTT não está
/// conectado e persiste no mesmo fluxo de armazenamento local do app.
final localMetricCollectorProvider = Provider<void>((ref) {
  Timer? timer;

  Future<void> collect() async {
    final mqttStatus = ref.read(mqttStatusProvider);
    if (mqttStatus.phase == MqttConnectionPhase.connected) {
      return;
    }

    try {
      final host = await ref.read(espLocalHostStoreProvider).loadHost();
      final payload = await ref
          .read(localMeasurementServiceProvider)
          .fetchMetricsPayload(espHost: host);
      final metric = parseMetricFromMqtt(payload);
      if (metric == null) {
        return;
      }

      final repo = ref.read(metricRepositoryProvider);
      await repo.insertMetric(metric);
      await ref.read(deviceStorageProvider.notifier).updateFromPayload(payload);

      ref.invalidate(metricsProvider);
      ref.invalidate(metricsByRangeProvider);
    } catch (_) {
      // Coleta local é oportunista: ignora erros de rede para não poluir a UI.
    }
  }

  unawaited(collect());
  timer = Timer.periodic(AppConfig.localCollectorInterval, (_) {
    unawaited(collect());
  });

  ref.onDispose(() => timer?.cancel());
});
