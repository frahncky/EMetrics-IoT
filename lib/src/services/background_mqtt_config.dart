import 'package:shared_preferences/shared_preferences.dart';

class BackgroundMqttConfig {
  final String broker;
  final String clientId;
  final String topic;
  final String requestTopic;

  const BackgroundMqttConfig({
    required this.broker,
    required this.clientId,
    required this.topic,
    required this.requestTopic,
  });

  static BackgroundMqttConfig fromPrefs(SharedPreferences prefs) {
    return BackgroundMqttConfig(
      broker: prefs.getString('mqtt_broker') ?? 'test.mosquitto.org',
      clientId: prefs.getString('mqtt_client_id') ?? 'emetrics_app',
      topic: prefs.getString('mqtt_topic') ?? 'emetrics/pzem',
      requestTopic:
          prefs.getString('mqtt_request_topic') ?? 'emetrics/pzem/history/request',
    );
  }
}