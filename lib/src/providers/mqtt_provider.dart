import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mqtt_service.dart';
import 'mqtt_settings_provider.dart';
import 'mqtt_status_provider.dart';

final mqttServiceProvider = Provider<MqttService>((ref) {
  final settings = ref.watch(mqttSettingsProvider);
  final status = ref.read(mqttStatusProvider.notifier);
  return MqttService(
    broker: settings.broker,
    port: settings.port,
    clientId: settings.clientId,
    username: settings.username,
    password: settings.password,
    topic: settings.topic,
    requestTopic: settings.requestTopic,
    useTls: settings.useTls,
    onConnecting: status.markConnecting,
    onConnected: status.markConnected,
    onDisconnectedStatus: status.markDisconnected,
    onError: status.markError,
  );
});
