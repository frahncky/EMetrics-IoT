import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/app_config.dart';

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
    client.setProtocolV311();
    client.connectTimeoutPeriod = 10000;
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
    final usernameTrimmed = username.trim();
    final passwordTrimmed = password.trim();
    final hasUsername = usernameTrimmed.isNotEmpty;
    final hasPassword = passwordTrimmed.isNotEmpty;

    if (!hasUsername && hasPassword) {
      throw const MqttServiceException(
        'Informe o usuário MQTT antes de preencher a senha.',
      );
    }

    final connectMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    final hasCredentials = hasUsername;
    if (hasCredentials) {
      connectMessage.authenticateAs(usernameTrimmed, passwordTrimmed);
    }
    client.connectionMessage = connectMessage;

    developer.log(
      'Iniciando conexão MQTT em $broker:$port',
      name: 'MqttService',
    );

    try {
      await client.connect();

      final state = client.connectionStatus?.state;
      if (state != MqttConnectionState.connected) {
        final code =
            client.connectionStatus?.returnCode?.name ?? 'desconhecido';
        client.disconnect();
        developer.log(
          'Broker MQTT recusou conexão. Código: $code',
          name: 'MqttService',
        );
        const message = 'Broker MQTT recusou a conexão.';
        onDisconnectedStatus?.call(message);
        throw const MqttServiceException(message);
      }
      onConnected?.call();
    } on NoConnectionException catch (e) {
      final message = _connectionFailureMessage(e);
      developer.log('Erro de conexão MQTT: $e', name: 'MqttService');
      onError?.call(message);
      throw MqttServiceException(message);
    } on SocketException catch (e) {
      final message = _connectionFailureMessage(e);
      developer.log('Erro de conexão MQTT: ${e.message}', name: 'MqttService');
      onError?.call(message);
      throw MqttServiceException(message);
    } on HandshakeException catch (e) {
      final message = _connectionFailureMessage(e);
      developer.log('Erro TLS MQTT: $e', name: 'MqttService');
      onError?.call(message);
      throw MqttServiceException(message);
    } on TimeoutException catch (e) {
      final message = _connectionFailureMessage(e);
      developer.log('Timeout MQTT: $e', name: 'MqttService');
      onError?.call(message);
      throw MqttServiceException(message);
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
      throw const MqttServiceException(
        'Erro inesperado ao conectar ao broker MQTT.',
      );
    }
  }

  String _connectionFailureMessage(Object error) {
    if (error is TimeoutException) {
      return 'Tempo esgotado ao conectar ao broker MQTT.';
    }
    if (error is HandshakeException) {
      return 'Falha TLS ao conectar ao broker MQTT.';
    }
    return 'Não foi possível conectar ao broker MQTT.';
  }

  /// Assina o [topic] configurado com QoS `atLeastOnce`.
  ///
  /// Deve ser chamado após [connect()] retornar sem erros.
  /// Lança [MqttServiceException] se o cliente não estiver conectado.
  void subscribe() {
    if (!isConnected) {
      throw const MqttServiceException(
        'Conecte ao broker MQTT antes de se inscrever em tópicos.',
      );
    }

    final result = client.subscribe(topic, MqttQos.atLeastOnce);
    if (result == null) {
      throw const MqttServiceException(
        'Falha ao assinar o tópico MQTT configurado.',
      );
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
  Future<void> requestHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!isConnected) {
      throw const MqttServiceException(
        'Conecte ao broker MQTT antes de solicitar histórico.',
      );
    }
    if (to.isBefore(from)) {
      throw const MqttServiceException(
        'Período inválido para solicitação de histórico.',
      );
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
        throw const MqttServiceException(
          'Falha ao montar a mensagem de solicitação de histórico.',
        );
      }
      client.publishMessage(requestTopic, MqttQos.atLeastOnce, data);
      developer.log(
        'Solicitação de histórico publicada em $requestTopic',
        name: 'MqttService',
      );
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

  /// Publica a configuracao de armazenamento e cadencia do medidor.
  ///
  /// O firmware ESP32 consome esse comando no mesmo [requestTopic] usado por
  /// solicitacoes de historico.
  Future<void> configureDeviceStorage({
    required int sdRetentionDays,
    required int measurementIntervalMs,
    required int sdLogIntervalMs,
    required int mqttPublishIntervalMs,
  }) async {
    if (!isConnected) {
      throw const MqttServiceException(
        'Conecte ao broker MQTT antes de configurar o armazenamento do medidor.',
      );
    }
    if (sdRetentionDays < 1 || sdRetentionDays > 3650) {
      throw const MqttServiceException(
        'A retenção do SD deve estar entre 1 e 3650 dias.',
      );
    }
    final intervals = [
      measurementIntervalMs,
      sdLogIntervalMs,
      mqttPublishIntervalMs,
    ];
    if (intervals.any((value) => value < 100 || value > 60000)) {
      throw const MqttServiceException(
        'Os intervalos do medidor devem estar entre 100 e 60000 ms.',
      );
    }

    try {
      final payload = jsonEncode({
        'command': 'configureStorage',
        'sdRetentionDays': sdRetentionDays,
        'measurementIntervalMs': measurementIntervalMs,
        'sdLogIntervalMs': sdLogIntervalMs,
        'mqttPublishIntervalMs': mqttPublishIntervalMs,
        'requestedAt': DateTime.now().millisecondsSinceEpoch,
      });
      final builder = MqttClientPayloadBuilder()..addString(payload);
      final data = builder.payload;
      if (data == null) {
        throw const MqttServiceException(
          'Falha ao montar a mensagem de configuração do medidor.',
        );
      }
      client.publishMessage(requestTopic, MqttQos.atLeastOnce, data);
      developer.log(
        'Configuração de armazenamento publicada em $requestTopic',
        name: 'MqttService',
      );
    } on MqttServiceException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log(
        'Erro ao publicar configuração de armazenamento',
        name: 'MqttService',
        error: e,
        stackTrace: stackTrace,
      );
      throw const MqttServiceException(
        'Erro ao configurar armazenamento do medidor via MQTT.',
      );
    }
  }

  /// Publica o comando de reset de energia no [requestTopic].
  ///
  /// O firmware ESP32 zera os contadores kWh/kVAh/kVArh do PZEM ao receber
  /// `{"command":"resetEnergy"}` no tópico de requisição.
  Future<void> resetEnergy() async {
    if (!isConnected) {
      throw const MqttServiceException(
        'Conecte ao broker MQTT antes de zerar a energia.',
      );
    }

    try {
      final payload = jsonEncode({
        'command': 'resetEnergy',
        'requestedAt': DateTime.now().millisecondsSinceEpoch,
      });
      final builder = MqttClientPayloadBuilder()..addString(payload);
      final data = builder.payload;
      if (data == null) {
        throw const MqttServiceException(
          'Falha ao montar o comando de reset de energia.',
        );
      }
      client.publishMessage(requestTopic, MqttQos.atLeastOnce, data);
      developer.log(
        'Comando resetEnergy publicado em $requestTopic',
        name: 'MqttService',
      );
    } on MqttServiceException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log(
        'Erro ao publicar resetEnergy',
        name: 'MqttService',
        error: e,
        stackTrace: stackTrace,
      );
      throw const MqttServiceException(
        'Erro ao enviar comando de reset de energia via MQTT.',
      );
    }
  }

  /// Tenta conectar com backoff exponencial.
  ///
  /// Cada falha dobra o intervalo de espera (mínimo [AppConfig.mqttRetryBaseDelay],
  /// máximo [AppConfig.mqttRetryMaxDelay]), até [AppConfig.mqttRetryMaxAttempts]
  /// tentativas. Relança o último [MqttServiceException] se todas falharem.
  Future<void> connectWithRetry() async {
    var delay = AppConfig.mqttRetryBaseDelay;
    MqttServiceException? last;

    for (
      var attempt = 1;
      attempt <= AppConfig.mqttRetryMaxAttempts;
      attempt++
    ) {
      try {
        await connect();
        return;
      } on MqttServiceException catch (e) {
        last = e;
        if (attempt == AppConfig.mqttRetryMaxAttempts) break;
        developer.log(
          'Tentativa $attempt/${AppConfig.mqttRetryMaxAttempts} falhou. '
          'Próxima em ${delay.inSeconds}s.',
          name: 'MqttService',
        );
        await Future.delayed(delay);
        final next = delay.inSeconds * 2;
        delay = Duration(
          seconds: next.clamp(
            AppConfig.mqttRetryBaseDelay.inSeconds,
            AppConfig.mqttRetryMaxDelay.inSeconds,
          ),
        );
      }
    }
    throw last!;
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
