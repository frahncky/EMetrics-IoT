import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/background_mqtt_service.dart';
import '../services/mqtt_service.dart';
import 'mqtt_settings_provider.dart';
import 'mqtt_status_provider.dart';

typedef HistoryRequestHandler = Future<void> Function({
  required DateTime from,
  required DateTime to,
});

typedef BackgroundHistoryRequestHandler = Future<void> Function({
  required DateTime from,
  required DateTime to,
});

final mqttServiceProvider = Provider<MqttService>((ref) {
  final settings = ref.watch(mqttSettingsProvider);
  final status = ref.read(mqttStatusProvider.notifier);
  final service = MqttService(
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
  ref.onDispose(service.disconnect);
  return service;
});

final backgroundHistoryRequestProvider = Provider<BackgroundHistoryRequestHandler>((
  ref,
) {
  return ({required DateTime from, required DateTime to}) {
    return BackgroundMqttService.requestHistory(from: from, to: to);
  };
});

/// Provider do handler de solicitação de histórico MQTT.
///
/// Quando o serviço em segundo plano está ativo ([MqttStatusState.backgroundActive]),
/// delega a requisição ao [BackgroundMqttService]; caso contrário, usa a
/// instância foreground [MqttService]. Isso garante que a solicitação seja
/// sempre roteada pelo canal MQTT correto independente do ciclo de vida do app.
final historyRequestHandlerProvider = Provider<HistoryRequestHandler>((ref) {
  final status = ref.watch(mqttStatusProvider);
  final mqttService = ref.read(mqttServiceProvider);
  final backgroundRequest = ref.read(backgroundHistoryRequestProvider);

  return ({required DateTime from, required DateTime to}) async {
    if (status.backgroundActive) {
      await backgroundRequest(from: from, to: to);
      return;
    }
    await mqttService.requestHistory(from: from, to: to);
  };
});
