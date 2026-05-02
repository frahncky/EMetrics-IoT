import 'package:shared_preferences/shared_preferences.dart';

class BackgroundMqttConfig {
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

  static BackgroundMqttConfig fromPrefs(SharedPreferences prefs) {
    return BackgroundMqttConfig(
      broker: prefs.getString('mqtt_broker') ?? 'test.mosquitto.org',
      port: prefs.getInt('mqtt_port') ?? 1883,
      clientId: prefs.getString('mqtt_client_id') ?? 'emetrics_app',
      username: prefs.getString('mqtt_username') ?? '',
      password: prefs.getString('mqtt_password') ?? '',
      topic: prefs.getString('mqtt_topic') ?? 'emetrics/pzem',
      requestTopic:
          prefs.getString('mqtt_request_topic') ?? 'emetrics/pzem/history/request',
      useTls: prefs.getBool('mqtt_use_tls') ?? false,
    );
  }
}