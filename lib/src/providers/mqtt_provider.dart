import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mqtt_service.dart';

final mqttServiceProvider = Provider<MqttService>((ref) {
  // Configurações podem vir de um provider de settings futuramente
  return MqttService(
    broker: 'test.mosquitto.org',
    clientId: 'emetrics_app',
    topic: 'emetrics/pzem',
  );
});
