import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'alert_history_provider.dart';
import 'alert_provider.dart';
import 'device_storage_provider.dart';
import 'local_metric_collector_provider.dart';
import 'metric_provider.dart';
import 'mqtt_metric_saver.dart';
import 'mqtt_status_provider.dart';

/// Ativa todos os providers de efeito colateral do app em um único ponto.
///
/// Substitui os múltiplos `ref.listen` encadeados em `_AppInitializer`,
/// tornando cada responsabilidade rastreável e testável de forma independente.
final appBootstrapProvider = Provider<void>((ref) {
  // Providers auto-gerenciados: basta observá-los para mantê-los vivos.
  ref.watch(alertProvider);
  ref.watch(deviceStorageTrackerProvider);
  ref.watch(localMetricCollectorProvider);
  ref.watch(integrationAutoSyncProvider);
  ref.watch(mqttMetricSaverProvider);

  // Eventos de conexão do serviço MQTT em segundo plano → atualiza o status.
  ref.listen(backgroundMqttConnectionEventsProvider, (_, next) {
    next.whenData(
      (event) => ref
          .read(mqttStatusProvider.notifier)
          .applyBackgroundConnectionEvent(event),
    );
  });

  // Métrica persistida em segundo plano → invalida caches de métricas e alertas.
  ref.listen(backgroundMqttMetricPersistedProvider, (_, next) {
    next.whenData((_) {
      ref.invalidate(metricsProvider);
      ref.invalidate(metricsByRangeProvider);
      ref.invalidate(alertHistoryProvider);
    });
  });
});
