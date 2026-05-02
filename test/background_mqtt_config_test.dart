import 'package:e_metrics_iot/src/services/background_mqtt_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BackgroundMqttConfig', () {
    test('usa valores padrão quando prefs estão vazias', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final config = BackgroundMqttConfig.fromPrefs(prefs);

      expect(config.broker, 'test.mosquitto.org');
      expect(config.port, 1883);
      expect(config.clientId, 'emetrics_app');
      expect(config.username, '');
      expect(config.password, '');
      expect(config.topic, 'emetrics/pzem');
      expect(config.requestTopic, 'emetrics/pzem/history/request');
      expect(config.useTls, isFalse);
    });

    test('lê valores salvos no shared preferences', () async {
      SharedPreferences.setMockInitialValues({
        'mqtt_broker': 'broker.hivemq.com',
        'mqtt_port': 8883,
        'mqtt_client_id': 'client_123',
        'mqtt_username': 'energia',
        'mqtt_password': 'segredo',
        'mqtt_topic': 'energia/medidor',
        'mqtt_request_topic': 'energia/medidor/history/request',
        'mqtt_use_tls': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final config = BackgroundMqttConfig.fromPrefs(prefs);

      expect(config.broker, 'broker.hivemq.com');
      expect(config.port, 8883);
      expect(config.clientId, 'client_123');
      expect(config.username, 'energia');
      expect(config.password, 'segredo');
      expect(config.topic, 'energia/medidor');
      expect(config.requestTopic, 'energia/medidor/history/request');
      expect(config.useTls, isTrue);
    });
  });
}
