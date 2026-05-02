import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MqttSettings {
  final String broker;
  final int port;
  final String clientId;
  final String username;
  final String password;
  final String topic;
  final String requestTopic;
  final bool useTls;

  const MqttSettings({
    required this.broker,
    required this.port,
    required this.clientId,
    required this.username,
    required this.password,
    required this.topic,
    required this.requestTopic,
    required this.useTls,
  });

  MqttSettings copyWith({
    String? broker,
    int? port,
    String? clientId,
    String? username,
    String? password,
    String? topic,
    String? requestTopic,
    bool? useTls,
  }) {
    return MqttSettings(
      broker: broker ?? this.broker,
      port: port ?? this.port,
      clientId: clientId ?? this.clientId,
      username: username ?? this.username,
      password: password ?? this.password,
      topic: topic ?? this.topic,
      requestTopic: requestTopic ?? this.requestTopic,
      useTls: useTls ?? this.useTls,
    );
  }
}

class MqttSettingsNotifier extends StateNotifier<MqttSettings> {
  static const _brokerKey = 'mqtt_broker';
  static const _portKey = 'mqtt_port';
  static const _clientIdKey = 'mqtt_client_id';
  static const _usernameKey = 'mqtt_username';
  static const _passwordKey = 'mqtt_password';
  static const _topicKey = 'mqtt_topic';
  static const _requestTopicKey = 'mqtt_request_topic';
  static const _useTlsKey = 'mqtt_use_tls';

  MqttSettingsNotifier()
      : super(
          const MqttSettings(
            broker: 'test.mosquitto.org',
            port: 1883,
            clientId: 'emetrics_app',
            username: '',
            password: '',
            topic: 'emetrics/pzem',
            requestTopic: 'emetrics/pzem/history/request',
            useTls: false,
          ),
        ) {
    load();
  }

  Future<MqttSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      broker: prefs.getString(_brokerKey) ?? state.broker,
      port: prefs.getInt(_portKey) ?? state.port,
      clientId: prefs.getString(_clientIdKey) ?? state.clientId,
      username: prefs.getString(_usernameKey) ?? state.username,
      password: prefs.getString(_passwordKey) ?? state.password,
      topic: prefs.getString(_topicKey) ?? state.topic,
      requestTopic: prefs.getString(_requestTopicKey) ?? state.requestTopic,
      useTls: prefs.getBool(_useTlsKey) ?? state.useTls,
    );
    return state;
  }

  Future<void> update({
    required String broker,
    required int port,
    required String clientId,
    required String username,
    required String password,
    required String topic,
    required String requestTopic,
    required bool useTls,
  }) async {
    state = state.copyWith(
      broker: broker.trim(),
      port: port,
      clientId: clientId.trim(),
      username: username.trim(),
      password: password,
      topic: topic.trim(),
      requestTopic: requestTopic.trim(),
      useTls: useTls,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brokerKey, state.broker);
    await prefs.setInt(_portKey, state.port);
    await prefs.setString(_clientIdKey, state.clientId);
    await prefs.setString(_usernameKey, state.username);
    await prefs.setString(_passwordKey, state.password);
    await prefs.setString(_topicKey, state.topic);
    await prefs.setString(_requestTopicKey, state.requestTopic);
    await prefs.setBool(_useTlsKey, state.useTls);
  }
}

final mqttSettingsProvider =
    StateNotifierProvider<MqttSettingsNotifier, MqttSettings>(
  (ref) => MqttSettingsNotifier(),
);
