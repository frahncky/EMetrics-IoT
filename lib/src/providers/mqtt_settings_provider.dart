import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _brokerKey = 'mqtt_broker';
  static const _clientIdKey = 'mqtt_client_id';
  static const _topicKey = 'mqtt_topic';
  static const _requestTopicKey = 'mqtt_request_topic';

  MqttSettingsNotifier()
      : super(
          const MqttSettings(
            broker: 'test.mosquitto.org',
            clientId: 'emetrics_app',
            topic: 'emetrics/pzem',
            requestTopic: 'emetrics/pzem/history/request',
          ),
        ) {
    load();
  }

  Future<MqttSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      broker: prefs.getString(_brokerKey) ?? state.broker,
      clientId: prefs.getString(_clientIdKey) ?? state.clientId,
      topic: prefs.getString(_topicKey) ?? state.topic,
      requestTopic: prefs.getString(_requestTopicKey) ?? state.requestTopic,
    );
    return state;
  }

  Future<void> update({
    required String broker,
    required String clientId,
    required String topic,
    required String requestTopic,
  }) async {
    state = state.copyWith(
      broker: broker.trim(),
      clientId: clientId.trim(),
      topic: topic.trim(),
      requestTopic: requestTopic.trim(),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brokerKey, state.broker);
    await prefs.setString(_clientIdKey, state.clientId);
    await prefs.setString(_topicKey, state.topic);
    await prefs.setString(_requestTopicKey, state.requestTopic);
  }
}

final mqttSettingsProvider =
    StateNotifierProvider<MqttSettingsNotifier, MqttSettings>(
  (ref) => MqttSettingsNotifier(),
);
