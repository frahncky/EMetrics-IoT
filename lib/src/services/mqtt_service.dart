
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

/// Cliente MQTT do app para conexão com broker IoT.
///
/// Encapsula o [MqttServerClient] com autenticação, TLS opcional,
/// subscrição de tópicos e publicação de solicitações de histórico.
/// Todos os callbacks de ciclo de vida são opcionais e acionados nos
/// estados `connecting`, `connected`, `disconnected` e `error`.
class MqttService {
  final String broker;
  final String clientId;
  final String username;
  final String password;
  final String topic;
  final String requestTopic;
  final int port;
  final bool useTls;
  final void Function()? onConnecting;
  final void Function()? onConnected;
  final void Function(String message)? onDisconnectedStatus;
  final void Function(String message)? onError;

  late MqttServerClient client;

  MqttService({
    required this.broker,
    required this.clientId,
    required this.topic,
    String? requestTopic,
    this.username = '',
    this.password = '',
    this.port = 1883,
    this.useTls = false,
    this.onConnecting,
    this.onConnected,
    this.onDisconnectedStatus,
    this.onError,
  }) : requestTopic = requestTopic ?? '$topic/history/request' {
    client = MqttServerClient(broker, clientId);
    client.port = port;
    client.secure = useTls;
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    // Desativa logs verbosos internos do mqtt_client em produção.
    client.logging(on: false);
    client.autoReconnect = true;
  }

  /// Inicia a conexão com o broker MQTT configurado.
  ///
  /// Requer que [WidgetsBinding.ensureInitialized()] tenha sido chamado antes.
  /// Lança [MqttServiceException] em caso de falha na autenticação ou rede.
  Future<void> connect() async {
    onConnecting?.call();
    final connectMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    final hasCredentials =
        username.trim().isNotEmpty || password.trim().isNotEmpty;
    if (hasCredentials) {
      connectMessage.authenticateAs(username, password);
    }
    client.connectionMessage = connectMessage;

    developer.log('Iniciando conexão MQTT em $broker:$port', name: 'MqttService');

    try {
      await client.connect();

      final state = client.connectionStatus?.state;
      if (state != MqttConnectionState.connected) {
        final code = client.connectionStatus?.returnCode?.name ?? 'desconhecido';
        client.disconnect();
        onDisconnectedStatus?.call(
          'Não foi possível conectar ao broker MQTT (código: $code).',
        );
        throw MqttServiceException(
          'Não foi possível conectar ao broker MQTT (código: $code).',
        );
      }
      onConnected?.call();
    } on SocketException catch (e) {
      developer.log('Erro de conexão MQTT: ${e.message}', name: 'MqttService');
      onError?.call(
        'Não foi possível conectar ao broker MQTT. Verifique sua conexão de rede.',
      );
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
      onError?.call('Erro inesperado ao conectar ao broker MQTT.');
      throw const MqttServiceException('Erro inesperado ao conectar ao broker MQTT.');
    }
  }

  /// Assina o [topic] configurado com QoS `atLeastOnce`.
  ///
  /// Deve ser chamado após [connect()] retornar sem erros.
  /// Lança [MqttServiceException] se o cliente não estiver conectado.
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

  /// Retorna `true` quando o cliente está conectado ao broker.
  bool get isConnected =>
      client.connectionStatus?.state == MqttConnectionState.connected;

  /// Encerra a conexão com o broker de forma segura (idempotente).
  void disconnect() {
    if (client.connectionStatus?.state != MqttConnectionState.disconnected) {
      client.disconnect();
    }
  }

  /// Publica uma solicitação de histórico no tópico [requestTopic].
  ///
  /// O payload é um JSON com os campos:
  /// - `from`: epoch em milissegundos do início do período
  /// - `to`: epoch em milissegundos do fim do período
  /// - `requestedAt`: epoch em milissegundos da solicitação
  ///
  /// Lança [MqttServiceException] se [from] for posterior a [to].
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

  /// Callback interno invocado pelo [MqttServerClient] ao detectar desconexão.
  void onDisconnected() {
    developer.log('Cliente MQTT desconectado', name: 'MqttService');
    onDisconnectedStatus?.call('Cliente MQTT desconectado.');
  }

  /// Stream de mensagens recebidas nos tópicos assinados.
  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates =>
      client.updates ?? Stream<List<MqttReceivedMessage<MqttMessage>>>.empty();
}
