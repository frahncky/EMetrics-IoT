import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mqtt_service.dart';
import 'mqtt_settings_provider.dart';

final mqttServiceProvider = Provider<MqttService>((ref) {
  final settings = ref.watch(mqttSettingsProvider);
  return MqttService(
    broker: settings.broker,
    clientId: settings.clientId,
    topic: settings.topic,
    requestTopic: settings.requestTopic,
  );
});
