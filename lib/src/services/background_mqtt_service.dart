import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/metric_repository.dart';
import '../providers/mqtt_metric_parser.dart';
import 'background_mqtt_config.dart';
import 'mqtt_credentials_store.dart';
import 'mqtt_service.dart';

class BackgroundMqttService {
  static const _notificationChannelId = 'mqtt_background_channel';
  static const _notificationId = 101;

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
          initialNotificationContent: 'Monitoramento MQTT em segundo plano ativo.',
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
        'O monitoramento em segundo plano nao esta ativo.',
      );
    }

    service.invoke('requestHistory', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? mqttSub;
    Timer? reconnectTimer;
    MqttService? mqtt;
    BackgroundMqttConfig? activeConfig;

    Future<void> connectAndListen() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final credentialsStore = SecureMqttCredentialsStore();
        final config = await BackgroundMqttConfig.fromStorage(
          prefs,
          credentialsStore,
        );

        final configChanged =
            activeConfig != null && !activeConfig!.sameConnectionProfile(config);

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
          final metric = parseMetricFromMqtt(payloadString);
          if (metric != null) {
            final repo = MetricRepository();
            await repo.insertMetric(metric);
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

    service.on('requestHistory').listen((payload) async {
      try {
        final data = payload ?? const <Object?, Object?>{};
        final fromMillis = data['from'];
        final toMillis = data['to'];
        if (fromMillis is! int || toMillis is! int) {
          return;
        }

        if (mqtt == null || !mqtt!.isConnected) {
          await connectAndListen();
        }
        if (mqtt == null || !mqtt!.isConnected) {
          throw const MqttServiceException(
            'Nao foi possivel conectar ao broker MQTT em segundo plano.',
          );
        }

        await mqtt!.requestHistory(
          from: DateTime.fromMillisecondsSinceEpoch(fromMillis),
          to: DateTime.fromMillisecondsSinceEpoch(toMillis),
        );
      } catch (e, stackTrace) {
        developer.log(
          'Falha ao solicitar historico via servico MQTT em segundo plano',
          name: 'BackgroundMqttService',
          error: e,
          stackTrace: stackTrace,
        );
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