import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_provider.dart';

final mqttStreamProvider = StreamProvider<List<MqttReceivedMessage<MqttMessage>>>((ref) {
  final mqtt = ref.watch(mqttServiceProvider);
  // A conexão deve ser feita manualmente pelo usuário, por exemplo, via botão nas configurações
  return mqtt.updates;
});
