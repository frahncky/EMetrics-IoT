import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/background_mqtt_service.dart';
import 'mqtt_settings_provider.dart';

typedef BackgroundRunningCheck = Future<bool> Function();

enum MqttConnectionPhase { disconnected, connecting, connected, error }

class MqttStatusState {
  final String broker;
  final int port;
  final String topic;
  final bool useTls;
  final MqttConnectionPhase phase;
  final bool backgroundActive;
  final DateTime? lastConnectedAt;
  final String? lastMessage;

  const MqttStatusState({
    required this.broker,
    required this.port,
    required this.topic,
    required this.useTls,
    required this.phase,
    required this.backgroundActive,
    this.lastConnectedAt,
    this.lastMessage,
  });

  const MqttStatusState.initial()
    : broker = 'test.mosquitto.org',
      port = 1883,
      topic = 'emetrics/pzem',
      useTls = false,
      phase = MqttConnectionPhase.disconnected,
      backgroundActive = false,
      lastConnectedAt = null,
      lastMessage = null;

  MqttStatusState copyWith({
    String? broker,
    int? port,
    String? topic,
    bool? useTls,
    MqttConnectionPhase? phase,
    bool? backgroundActive,
    DateTime? lastConnectedAt,
    String? lastMessage,
    bool clearLastConnectedAt = false,
    bool clearLastMessage = false,
  }) {
    return MqttStatusState(
      broker: broker ?? this.broker,
      port: port ?? this.port,
      topic: topic ?? this.topic,
      useTls: useTls ?? this.useTls,
      phase: phase ?? this.phase,
      backgroundActive: backgroundActive ?? this.backgroundActive,
      lastConnectedAt: clearLastConnectedAt
          ? null
          : (lastConnectedAt ?? this.lastConnectedAt),
      lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }
}

class MqttStatusNotifier extends StateNotifier<MqttStatusState> {
  final BackgroundRunningCheck _backgroundRunningCheck;

  MqttStatusNotifier(this._backgroundRunningCheck)
    : super(const MqttStatusState.initial());

  void configure(MqttSettings settings) {
    state = state.copyWith(
      broker: settings.broker,
      port: settings.port,
      topic: settings.topic,
      useTls: settings.useTls,
    );
  }

  Future<void> syncBackgroundState() async {
    final isRunning = await _backgroundRunningCheck();
    setBackgroundActive(isRunning);
  }

  void markConnecting() {
    state = state.copyWith(
      phase: MqttConnectionPhase.connecting,
      lastMessage: 'Conectando ao broker MQTT...',
    );
  }

  void markConnected() {
    state = state.copyWith(
      phase: MqttConnectionPhase.connected,
      lastConnectedAt: DateTime.now(),
      lastMessage: 'Broker MQTT conectado.',
    );
  }

  void markDisconnected([String? reason]) {
    state = state.copyWith(
      phase: MqttConnectionPhase.disconnected,
      lastMessage: reason ?? 'Broker MQTT desconectado.',
    );
  }

  void markError(String message) {
    state = state.copyWith(phase: MqttConnectionPhase.error, lastMessage: message);
  }

  void setBackgroundActive(bool isActive) {
    state = state.copyWith(backgroundActive: isActive);
  }
}

final mqttBackgroundRunningCheckProvider = Provider<BackgroundRunningCheck>((
  ref,
) {
  return BackgroundMqttService.isRunning;
});

final mqttStatusProvider =
    StateNotifierProvider<MqttStatusNotifier, MqttStatusState>((ref) {
      final notifier = MqttStatusNotifier(
        ref.read(mqttBackgroundRunningCheckProvider),
      );
      notifier.configure(ref.read(mqttSettingsProvider));
      ref.listen<MqttSettings>(mqttSettingsProvider, (previous, next) {
        notifier.configure(next);
      });
      return notifier;
    });