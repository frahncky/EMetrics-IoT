import 'package:flutter_riverpod/flutter_riverpod.dart';

class MqttSettings {
  final String broker;
  final String clientId;
  final String topic;
  final String requestTopic;

  const MqttSettings({
    required this.broker,
    required this.clientId,
    required this.topic,
    required this.requestTopic,
  });

  MqttSettings copyWith({
    String? broker,
    String? clientId,
    String? topic,
    String? requestTopic,
  }) {
    return MqttSettings(
      broker: broker ?? this.broker,
      clientId: clientId ?? this.clientId,
      topic: topic ?? this.topic,
      requestTopic: requestTopic ?? this.requestTopic,
    );
  }
}

class MqttSettingsNotifier extends StateNotifier<MqttSettings> {
  MqttSettingsNotifier()
      : super(
          const MqttSettings(
            broker: 'test.mosquitto.org',
            clientId: 'emetrics_app',
            topic: 'emetrics/pzem',
            requestTopic: 'emetrics/pzem/history/request',
          ),
        );

  void update({
    required String broker,
    required String clientId,
    required String topic,
    required String requestTopic,
  }) {
    state = state.copyWith(
      broker: broker.trim(),
      clientId: clientId.trim(),
      topic: topic.trim(),
      requestTopic: requestTopic.trim(),
    );
  }
}

final mqttSettingsProvider =
    StateNotifierProvider<MqttSettingsNotifier, MqttSettings>(
  (ref) => MqttSettingsNotifier(),
);
