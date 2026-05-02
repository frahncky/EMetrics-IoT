import 'package:shared_preferences/shared_preferences.dart';

import 'mqtt_credentials_store.dart';

class BackgroundMqttConfig {
  static const _legacyUsernameKey = 'mqtt_username';
  static const _legacyPasswordKey = 'mqtt_password';

  final String broker;
  final int port;
  final String clientId;
  final String username;
  final String password;
  final String topic;
  final String requestTopic;
  final bool useTls;

  const BackgroundMqttConfig({
    required this.broker,
    required this.port,
    required this.clientId,
    required this.username,
    required this.password,
    required this.topic,
    required this.requestTopic,
    required this.useTls,
  });

  bool sameConnectionProfile(BackgroundMqttConfig other) {
    return broker == other.broker &&
        port == other.port &&
        clientId == other.clientId &&
        username == other.username &&
        password == other.password &&
        topic == other.topic &&
        requestTopic == other.requestTopic &&
        useTls == other.useTls;
  }

  static Future<BackgroundMqttConfig> fromStorage(
    SharedPreferences prefs,
    MqttCredentialsStore credentialsStore,
  ) async {
    String username = await credentialsStore.readUsername();
    String password = await credentialsStore.readPassword();

    // One-time migration for legacy insecure keys.
    if (username.isEmpty && password.isEmpty) {
      final legacyUsername = prefs.getString(_legacyUsernameKey) ?? '';
      final legacyPassword = prefs.getString(_legacyPasswordKey) ?? '';
      if (legacyUsername.isNotEmpty || legacyPassword.isNotEmpty) {
        username = legacyUsername;
        password = legacyPassword;
        await credentialsStore.writeCredentials(
          username: legacyUsername,
          password: legacyPassword,
        );
        await prefs.remove(_legacyUsernameKey);
        await prefs.remove(_legacyPasswordKey);
      }
    }

    return BackgroundMqttConfig(
      broker: prefs.getString('mqtt_broker') ?? 'test.mosquitto.org',
      port: prefs.getInt('mqtt_port') ?? 1883,
      clientId: prefs.getString('mqtt_client_id') ?? 'emetrics_app',
      username: username,
      password: password,
      topic: prefs.getString('mqtt_topic') ?? 'emetrics/pzem',
      requestTopic:
          prefs.getString('mqtt_request_topic') ?? 'emetrics/pzem/history/request',
      useTls: prefs.getBool('mqtt_use_tls') ?? false,
    );
  }
}