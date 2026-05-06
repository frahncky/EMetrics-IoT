import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/metric_repository.dart';
import 'device_storage_status_store.dart';
import '../providers/mqtt_metric_parser.dart';
import 'background_mqtt_config.dart';
import 'mqtt_credentials_store.dart';
import 'mqtt_service.dart';
import 'storage_settings_store.dart';

class BackgroundMqttService {
  static const _notificationChannelId = 'mqtt_background_channel';
  static const _notificationId = 101;
  static const _historyRequestEvent = 'requestHistory';
  static const _historyRequestResultEvent = 'requestHistoryResult';
  static const _storageConfigEvent = 'configureDeviceStorage';
  static const _storageConfigResultEvent = 'configureDeviceStorageResult';

  static Future<bool> isRunning() async {
    try {
      final service = FlutterBackgroundService();
      return service.isRunning();
    } catch (_) {
      return false;
    }
  }

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    try {
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          autoStartOnBoot: true,
          notificationChannelId: _notificationChannelId,
          initialNotificationTitle: 'E-Metrics IoT',
          initialNotificationContent:
              'Monitoramento MQTT em segundo plano ativo.',
          foregroundServiceNotificationId: _notificationId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
        ),
      );
    } catch (_) {
      return;
    }
  }

  static Future<bool> start() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
      }
      return await service.isRunning();
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
    } catch (_) {
      return;
    }
  }

  static Future<void> requestHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      throw const MqttServiceException(
        'O monitoramento em segundo plano não está ativo.',
      );
    }

    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}_${from.millisecondsSinceEpoch}_${to.millisecondsSinceEpoch}';

    service.invoke(_historyRequestEvent, {
      'requestId': requestId,
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });

    final response = await service
        .on(_historyRequestResultEvent)
        .firstWhere((payload) => payload?['requestId'] == requestId)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException(
            'Tempo limite ao solicitar histórico em segundo plano.',
          ),
        );

    final ok = response?['ok'] == true;
    if (!ok) {
      final rawError = response?['error'];
      final message = rawError is String && rawError.trim().isNotEmpty
          ? rawError
          : 'Falha ao solicitar histórico no monitoramento em segundo plano.';
      throw MqttServiceException(message);
    }
  }

  static Future<void> configureDeviceStorageRetention({
    required int sdRetentionDays,
  }) async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      throw const MqttServiceException(
        'O monitoramento em segundo plano não está ativo.',
      );
    }

    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}_storage_$sdRetentionDays';

    service.invoke(_storageConfigEvent, {
      'requestId': requestId,
      'sdRetentionDays': sdRetentionDays,
    });

    final response = await service
        .on(_storageConfigResultEvent)
        .firstWhere((payload) => payload?['requestId'] == requestId)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException(
            'Tempo limite ao configurar armazenamento em segundo plano.',
          ),
        );

    final ok = response?['ok'] == true;
    if (!ok) {
      final rawError = response?['error'];
      final message = rawError is String && rawError.trim().isNotEmpty
          ? rawError
          : 'Falha ao configurar armazenamento no monitoramento em segundo plano.';
      throw MqttServiceException(message);
    }
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? mqttSub;
    Timer? reconnectTimer;
    MqttService? mqtt;
    BackgroundMqttConfig? activeConfig;
    DateTime? lastRetentionCleanupAt;

    Future<void> pruneLocalHistoryIfNeeded(MetricRepository repo) async {
      final now = DateTime.now();
      if (lastRetentionCleanupAt != null &&
          now.difference(lastRetentionCleanupAt!).inHours < 1) {
        return;
      }

      final storageSettings = await const StorageSettingsStore().load();
      final cutoff = now.subtract(
        Duration(days: storageSettings.localRetentionDays),
      );
      await repo.deleteMetricsOlderThan(cutoff);
      lastRetentionCleanupAt = now;
    }

    Future<void> connectAndListen() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final credentialsStore = SecureMqttCredentialsStore();
        final config = await BackgroundMqttConfig.fromStorage(
          prefs,
          credentialsStore,
        );

        final configChanged =
            activeConfig != null &&
            !activeConfig!.sameConnectionProfile(config);

        if (configChanged) {
          await mqttSub?.cancel();
          mqttSub = null;
          if (mqtt != null && mqtt!.isConnected) {
            mqtt!.disconnect();
          }
          mqtt = null;
        }

        mqtt ??= MqttService(
          broker: config.broker,
          port: config.port,
          useTls: config.useTls,
          clientId: '${config.clientId}_bg',
          username: config.username,
          password: config.password,
          topic: config.topic,
          requestTopic: config.requestTopic,
        );
        activeConfig = config;

        if (!mqtt!.isConnected) {
          await mqtt!.connect();
          mqtt!.subscribe();
        }

        await mqttSub?.cancel();
        mqttSub = mqtt!.updates.listen((messages) async {
          if (messages.isEmpty) {
            return;
          }
          final last = messages.last;
          final payload = (last.payload as MqttPublishMessage).payload.message;
          final payloadString = String.fromCharCodes(payload);
          final storageStatus = parseDeviceStorageStatusFromMqtt(payloadString);
          if (storageStatus != null) {
            await const DeviceStorageStatusStore().save(storageStatus);
          }
          final metric = parseMetricFromMqtt(payloadString);
          if (metric != null) {
            final repo = MetricRepository();
            await repo.insertMetric(metric);
            await pruneLocalHistoryIfNeeded(repo);
          }
        });

        if (service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'E-Metrics IoT',
            content: 'Recebendo métricas MQTT em segundo plano.',
          );
        }
      } catch (e, stackTrace) {
        developer.log(
          'Falha no serviço MQTT em segundo plano',
          name: 'BackgroundMqttService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    service.on('stopService').listen((_) async {
      reconnectTimer?.cancel();
      await mqttSub?.cancel();
      if (mqtt != null && mqtt!.isConnected) {
        mqtt!.disconnect();
      }
      await service.stopSelf();
    });

    service.on(_historyRequestEvent).listen((payload) async {
      final data = payload ?? <String, dynamic>{};
      final requestId = data['requestId'];

      Future<void> sendResult({required bool ok, String? error}) async {
        if (requestId is! String || requestId.isEmpty) {
          return;
        }
        service.invoke(_historyRequestResultEvent, {
          'requestId': requestId,
          'ok': ok,
          if (error != null && error.isNotEmpty) 'error': error,
        });
      }

      try {
        final fromMillis = data['from'];
        final toMillis = data['to'];
        if (fromMillis is! int || toMillis is! int) {
          await sendResult(
            ok: false,
            error: 'Payload inválido para solicitação de histórico.',
          );
          return;
        }

        if (mqtt == null || !mqtt!.isConnected) {
          await connectAndListen();
        }
        if (mqtt == null || !mqtt!.isConnected) {
          await sendResult(
            ok: false,
            error: 'Não foi possível conectar ao broker MQTT em segundo plano.',
          );
          return;
        }

        await mqtt!.requestHistory(
          from: DateTime.fromMillisecondsSinceEpoch(fromMillis),
          to: DateTime.fromMillisecondsSinceEpoch(toMillis),
        );
        await sendResult(ok: true);
      } catch (e, stackTrace) {
        developer.log(
          'Falha ao solicitar histórico via serviço MQTT em segundo plano',
          name: 'BackgroundMqttService',
          error: e,
          stackTrace: stackTrace,
        );
        await sendResult(ok: false, error: e.toString());
      }
    });

    service.on(_storageConfigEvent).listen((payload) async {
      final data = payload ?? <String, dynamic>{};
      final requestId = data['requestId'];

      Future<void> sendResult({required bool ok, String? error}) async {
        if (requestId is! String || requestId.isEmpty) {
          return;
        }
        service.invoke(_storageConfigResultEvent, {
          'requestId': requestId,
          'ok': ok,
          if (error != null && error.isNotEmpty) 'error': error,
        });
      }

      try {
        final sdRetentionDays = data['sdRetentionDays'];
        if (sdRetentionDays is! int) {
          await sendResult(
            ok: false,
            error: 'Payload inválido para configuração de armazenamento.',
          );
          return;
        }

        if (mqtt == null || !mqtt!.isConnected) {
          await connectAndListen();
        }
        if (mqtt == null || !mqtt!.isConnected) {
          await sendResult(
            ok: false,
            error: 'Não foi possível conectar ao broker MQTT em segundo plano.',
          );
          return;
        }

        await mqtt!.configureDeviceStorageRetention(
          sdRetentionDays: sdRetentionDays,
        );
        await sendResult(ok: true);
      } catch (e, stackTrace) {
        developer.log(
          'Falha ao configurar armazenamento via serviço MQTT em segundo plano',
          name: 'BackgroundMqttService',
          error: e,
          stackTrace: stackTrace,
        );
        await sendResult(ok: false, error: e.toString());
      }
    });

    reconnectTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (mqtt == null || !mqtt!.isConnected) {
        await connectAndListen();
      }
    });

    await connectAndListen();
  }
}
