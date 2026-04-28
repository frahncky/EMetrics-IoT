import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final String broker;
  final String clientId;
  final String username;
  final String password;
  final String topic;
  final int port;

  late MqttServerClient client;

  MqttService({
    required this.broker,
    required this.clientId,
    required this.topic,
    this.username = '',
    this.password = '',
    this.port = 1883,
  }) {
    client = MqttServerClient(broker, clientId);
    client.port = port;
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.logging(on: false);
    client.autoReconnect = true;
  }

  Future<void> connect() async {
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean();
    try {
      await client.connect();
    } catch (e) {
      rethrow;
    }
  }

  void subscribe() {
    client.subscribe(topic, MqttQos.atLeastOnce);
  }

  void onDisconnected() {
    // TODO: implementar reconexão e notificação visual
  }

  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates => client.updates!;
}
