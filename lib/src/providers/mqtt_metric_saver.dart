import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'metric_provider.dart';
import 'integration_settings_provider.dart';
import 'mqtt_stream_provider.dart';
import 'mqtt_metric_parser.dart';
import '../services/background_mqtt_service.dart';
import '../services/storage_settings_store.dart';
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

/// Provider que persiste métricas MQTT no banco local e dispara sincronização
/// com serviços de integração externos.
///
/// Garante duas propriedades críticas:
/// - **Serialização**: encadeia escritas em sequência para evitar condições de
///   corrida no SQLite durante alta frequência de mensagens.
/// - **Debounce**: agrupa invalidações de providers em janelas de 100 ms para
///   evitar reconstruções excessivas de widgets.
///
/// Deve ser observado (via `ref.watch`) na tela que precisa persistir dados;
/// quando não está sendo observado, nenhuma escrita é realizada.
final mqttMetricSaverProvider = Provider<void>((ref) {
  Future<void> lastOperation = Future.value();
  Timer? debounceTimer;
  DateTime? lastRetentionCleanupAt;

  ref.watch(mqttStreamProvider).whenData((messages) async {
    // Ignora se o serviço MQTT em segundo plano já está persistindo as métricas.
    final isBackgroundActive = await ref.read(backgroundRunningCheckProvider)();
    if (isBackgroundActive || messages.isEmpty) {
      return;
    }

    // Encadeia a nova operação após a anterior para garantir ordem de escrita.
    // ref.read() é seguro aqui pois o callback só executa quando o provider
    // ainda está ativo (preso pela cadeia lastOperation).
    lastOperation = lastOperation.then((_) async {
      final last = messages.last;
      final payload = (last.payload as MqttPublishMessage).payload.message;
      final payloadString = String.fromCharCodes(payload);
      final metric = parseMetricFromMqtt(payloadString);
      if (metric != null) {
        final repo = ref.read(metricRepositoryProvider);
        final activeProfile = ref.read(mqttSettingsProvider);
        await repo.insertMetric(metric);
        final now = DateTime.now();
        if (lastRetentionCleanupAt == null ||
            now.difference(lastRetentionCleanupAt!).inHours >= 1) {
          final storageSettings = await const StorageSettingsStore().load();
          final cutoff = now.subtract(
            Duration(days: storageSettings.localRetentionDays),
          );
          await repo.deleteMetricsOlderThan(cutoff);
          lastRetentionCleanupAt = now;
        }
        await ref
            .read(integrationServiceProvider)
            .submitMetric(metric, profileId: activeProfile.profileId);

        // Debounce: cancela e reagenda para que um burst de mensagens
        // dispare apenas uma invalidação ao final da ráfaga.
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 100), () {
          ref.invalidate(metricsProvider);
          ref.invalidate(metricsByRangeProvider);
        });
      }
    }).catchError((Object e, StackTrace st) {
      developer.log(
        'Falha ao persistir métrica MQTT',
        name: 'mqttMetricSaverProvider',
        error: e,
        stackTrace: st,
      );
    });
  });
});
