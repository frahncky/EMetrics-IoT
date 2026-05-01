
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttServiceException implements Exception {
  final String message;

  const MqttServiceException(this.message);

  @override
  String toString() => message;
}

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

    developer.log('Iniciando conexão MQTT em $broker:$port', name: 'MqttService');

    try {
      await client.connect();

      final state = client.connectionStatus?.state;
      if (state != MqttConnectionState.connected) {
        final code = client.connectionStatus?.returnCode?.name ?? 'desconhecido';
        client.disconnect();
        throw MqttServiceException(
          'Não foi possível conectar ao broker MQTT (código: $code).',
        );
      }
    } on SocketException catch (e) {
      developer.log('Erro de conexão MQTT: ${e.message}', name: 'MqttService');
      throw const MqttServiceException(
        'Não foi possível conectar ao broker MQTT. Verifique sua conexão de rede.',
      );
    } on MqttServiceException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log(
        'Erro inesperado ao conectar MQTT',
        name: 'MqttService',
        error: e,
        stackTrace: stackTrace,
      );
      throw const MqttServiceException('Erro inesperado ao conectar ao broker MQTT.');
    }
  }

  void subscribe() {
    if (!isConnected) {
      throw const MqttServiceException('Conecte ao broker MQTT antes de se inscrever em tópicos.');
    }

    final result = client.subscribe(topic, MqttQos.atLeastOnce);
    if (result == null) {
      throw const MqttServiceException('Falha ao assinar o tópico MQTT configurado.');
    }

    developer.log('Inscrito no tópico MQTT: $topic', name: 'MqttService');
  }

  bool get isConnected =>
      client.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> requestHistory({required DateTime from, required DateTime to}) async {
    if (!isConnected) {
      throw const MqttServiceException('Conecte ao broker MQTT antes de solicitar histórico.');
    }
    if (to.isBefore(from)) {
      throw const MqttServiceException('Período inválido para solicitação de histórico.');
    }

    try {
      final payload = jsonEncode({
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        'requestedAt': DateTime.now().millisecondsSinceEpoch,
      });
      final builder = MqttClientPayloadBuilder()..addString(payload);
      final data = builder.payload;
      if (data == null) {
        throw const MqttServiceException('Falha ao montar a mensagem de solicitação de histórico.');
      }
      client.publishMessage(requestTopic, MqttQos.atLeastOnce, data);
      developer.log('Solicitação de histórico publicada em $requestTopic', name: 'MqttService');
    } on MqttServiceException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log(
        'Erro ao publicar solicitação de histórico',
        name: 'MqttService',
        error: e,
        stackTrace: stackTrace,
      );
      throw const MqttServiceException('Erro ao solicitar histórico via MQTT.');
    }
  }

  void onDisconnected() {
    developer.log('Cliente MQTT desconectado', name: 'MqttService');
  }

  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates =>
      client.updates ?? Stream<List<MqttReceivedMessage<MqttMessage>>>.empty();
}
