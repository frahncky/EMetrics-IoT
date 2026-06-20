import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/metric_repository.dart';
import 'background_metric_processor.dart';
import 'alert_service.dart';
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
  static const _serviceReadyEvent = 'backgroundServiceReady';
  static const _connectionStateEvent = 'backgroundMqttConnectionState';
  static const _metricPersistedEvent = 'backgroundMqttMetricPersisted';

  static Stream<BackgroundMqttConnectionEvent> get connectionEvents {
    try {
      return FlutterBackgroundService()
          .on(_connectionStateEvent)
          .map(BackgroundMqttConnectionEvent.fromPayload);
    } catch (_) {
      return const Stream.empty();
    }
  }

  static Stream<void> get metricPersistedEvents {
    try {
      return FlutterBackgroundService().on(_metricPersistedEvent).map((_) {});
    } catch (_) {
      return const Stream.empty();
    }
  }

  static Future<bool> isRunning() async {
    try {
      final service = FlutterBackgroundService();
      return service.isRunning();
    } catch (e, st) {
      developer.log(
        'Falha ao verificar estado do serviço background',
        name: 'BackgroundMqttService',
        error: e,
        stackTrace: st,
      );
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
          autoStartOnBoot: false,
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
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
    } catch (e, st) {
      developer.log(
        'Falha ao configurar serviço background',
        name: 'BackgroundMqttService',
        error: e,
        stackTrace: st,
      );
      return;
    }
  }

  static Future<bool> start() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (isRunning) {
        return true;
      }

      final ready = service
          .on(_serviceReadyEvent)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      final started = await service.startService();
      if (!started) {
        return false;
      }
      await ready;
      return await service.isRunning();
    } catch (e, st) {
      developer.log(
        'Falha ao iniciar serviço background',
        name: 'BackgroundMqttService',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!await service.isRunning()) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (e, st) {
      developer.log(
        'Falha ao parar serviço background',
        name: 'BackgroundMqttService',
        error: e,
        stackTrace: st,
      );
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
    DartPluginRegistrant.ensureInitialized();
    try {
      await AlertService.init();
    } catch (error, stackTrace) {
      developer.log(
        'Falha ao inicializar notificações no serviço em segundo plano',
        name: 'BackgroundMqttService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? mqttSub;
    Timer? reconnectTimer;
    MqttService? mqtt;
    BackgroundMqttConfig? activeConfig;
    DateTime? lastRetentionCleanupAt;
    Future<void> metricProcessing = Future.value();
    final metricProcessor = BackgroundMetricProcessor();

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
        _emitConnectionEvent(service, BackgroundMqttConnectionPhase.connecting);
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

        _emitConnectionEvent(service, BackgroundMqttConnectionPhase.connected);

        mqttSub ??= mqtt!.updates.listen((messages) {
          if (messages.isEmpty) {
            return;
          }
          metricProcessing = metricProcessing
              .then((_) async {
                final last = messages.last;
                final payload =
                    (last.payload as MqttPublishMessage).payload.message;
                final payloadString = String.fromCharCodes(payload);
                final storageStatus = parseDeviceStorageStatusFromMqtt(
                  payloadString,
                );
                if (storageStatus != null) {
                  await const DeviceStorageStatusStore().save(storageStatus);
                }
                final metric = parseMetricFromMqtt(payloadString);
                if (metric == null) {
                  return;
                }

                final repo = MetricRepository();
                await repo.insertMetric(metric);
                await pruneLocalHistoryIfNeeded(repo);
                await metricProcessor.process(metric, repository: repo);
                service.invoke(_metricPersistedEvent);
              })
              .catchError((Object error, StackTrace stackTrace) {
                developer.log(
                  'Falha ao processar métrica MQTT em segundo plano',
                  name: 'BackgroundMqttService',
                  error: error,
                  stackTrace: stackTrace,
                );
              });
        });

        if (service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'E-Metrics IoT',
            content: 'Recebendo métricas MQTT em segundo plano.',
          );
        }
      } catch (e, stackTrace) {
        _emitConnectionEvent(
          service,
          BackgroundMqttConnectionPhase.error,
          message: _connectionErrorMessage(e),
        );
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
      _emitConnectionEvent(service, BackgroundMqttConnectionPhase.stopped);
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

    service.invoke(_serviceReadyEvent);

    reconnectTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (mqtt == null || !mqtt!.isConnected) {
        await connectAndListen();
      }
    });

    await connectAndListen();
  }

  static void _emitConnectionEvent(
    ServiceInstance service,
    BackgroundMqttConnectionPhase phase, {
    String? message,
  }) {
    service.invoke(_connectionStateEvent, {
      'phase': phase.name,
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  static String _connectionErrorMessage(Object error) {
    if (error is MqttServiceException) {
      return error.message;
    }
    return 'Não foi possível conectar ao broker MQTT em segundo plano.';
  }
}

enum BackgroundMqttConnectionPhase { connecting, connected, error, stopped }

class BackgroundMqttConnectionEvent {
  final BackgroundMqttConnectionPhase phase;
  final String? message;

  const BackgroundMqttConnectionEvent({required this.phase, this.message});

  factory BackgroundMqttConnectionEvent.fromPayload(
    Map<String, dynamic>? payload,
  ) {
    final rawPhase = payload?['phase'];
    final phase = rawPhase is String
        ? BackgroundMqttConnectionPhase.values.firstWhere(
            (value) => value.name == rawPhase,
            orElse: () => BackgroundMqttConnectionPhase.error,
          )
        : BackgroundMqttConnectionPhase.error;
    final rawMessage = payload?['message'];
    return BackgroundMqttConnectionEvent(
      phase: phase,
      message: rawMessage is String ? rawMessage : null,
    );
  }
}
