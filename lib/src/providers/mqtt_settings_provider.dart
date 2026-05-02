import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mqtt_credentials_store.dart';

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
  static const _topicKey = 'mqtt_topic';
  static const _requestTopicKey = 'mqtt_request_topic';
  static const _useTlsKey = 'mqtt_use_tls';

  // Legacy keys kept only for one-time migration.
  static const _legacyUsernameKey = 'mqtt_username';
  static const _legacyPasswordKey = 'mqtt_password';

  final MqttCredentialsStore _credentialsStore;

  MqttSettingsNotifier(this._credentialsStore)
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
    final currentState = state;
    final prefs = await SharedPreferences.getInstance();

    String username = await _credentialsStore.readUsername();
    String password = await _credentialsStore.readPassword();

    // One-time migration from old non-secure preferences keys.
    if (username.isEmpty && password.isEmpty) {
      final legacyUsername = prefs.getString(_legacyUsernameKey) ?? '';
      final legacyPassword = prefs.getString(_legacyPasswordKey) ?? '';
      if (legacyUsername.isNotEmpty || legacyPassword.isNotEmpty) {
        username = legacyUsername;
        password = legacyPassword;
        await _credentialsStore.writeCredentials(
          username: legacyUsername,
          password: legacyPassword,
        );
        await prefs.remove(_legacyUsernameKey);
        await prefs.remove(_legacyPasswordKey);
      }
    }

    final loadedState = currentState.copyWith(
      broker: prefs.getString(_brokerKey) ?? currentState.broker,
      port: prefs.getInt(_portKey) ?? currentState.port,
      clientId: prefs.getString(_clientIdKey) ?? currentState.clientId,
      username: username,
      password: password,
      topic: prefs.getString(_topicKey) ?? currentState.topic,
      requestTopic: prefs.getString(_requestTopicKey) ?? currentState.requestTopic,
      useTls: prefs.getBool(_useTlsKey) ?? currentState.useTls,
    );

    if (mounted) {
      state = loadedState;
    }
    return loadedState;
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
    final nextState = state.copyWith(
      broker: broker.trim(),
      port: port,
      clientId: clientId.trim(),
      username: username.trim(),
      password: password,
      topic: topic.trim(),
      requestTopic: requestTopic.trim(),
      useTls: useTls,
    );
    state = nextState;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brokerKey, nextState.broker);
    await prefs.setInt(_portKey, nextState.port);
    await prefs.setString(_clientIdKey, nextState.clientId);
    await prefs.setString(_topicKey, nextState.topic);
    await prefs.setString(_requestTopicKey, nextState.requestTopic);
    await prefs.setBool(_useTlsKey, nextState.useTls);

    await _credentialsStore.writeCredentials(
      username: nextState.username,
      password: nextState.password,
    );

    state = nextState;
  }
}

final mqttCredentialsStoreProvider = Provider<MqttCredentialsStore>(
  (ref) => SecureMqttCredentialsStore(),
);

final mqttSettingsProvider =
    StateNotifierProvider<MqttSettingsNotifier, MqttSettings>(
  (ref) => MqttSettingsNotifier(ref.watch(mqttCredentialsStoreProvider)),
);
