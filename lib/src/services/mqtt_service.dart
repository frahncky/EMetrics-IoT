
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final String broker;
  final String clientId;
  final String username;
  final String password;
  final String topic;
  final String requestTopic;
  final int port;

  late MqttServerClient client;

  MqttService({
    required this.broker,
    required this.clientId,
    required this.topic,
    String? requestTopic,
    this.username = '',
    this.password = '',
    this.port = 1883,
  }) : requestTopic = requestTopic ?? '$topic/history/request' {
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
    } on SocketException catch (e) {
      // Trate o erro de rede de forma amigável
      developer.log('Erro de conexão MQTT: ${e.message}', name: 'MqttService');
      // Aqui você pode exibir um alerta visual ou notificar o usuário
      throw Exception('Não foi possível conectar ao broker MQTT. Verifique sua conexão de rede.');
    } catch (e) {
      developer.log('Erro inesperado ao conectar MQTT: $e', name: 'MqttService');
      throw Exception('Erro inesperado ao conectar ao broker MQTT.');
    }
  }

  void subscribe() {
    client.subscribe(topic, MqttQos.atLeastOnce);
  }

  bool get isConnected =>
      client.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> requestHistory({required DateTime from, required DateTime to}) async {
    if (!isConnected) {
      throw Exception('Conecte ao broker MQTT antes de solicitar histórico.');
    }

    final payload = jsonEncode({
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
      'requestedAt': DateTime.now().millisecondsSinceEpoch,
    });
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(requestTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  void onDisconnected() {
    // TODO: implementar reconexão e notificação visual
  }

  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates =>
      client.updates ?? Stream<List<MqttReceivedMessage<MqttMessage>>>.empty();
}
