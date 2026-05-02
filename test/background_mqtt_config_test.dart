import 'package:e_metrics_iot/src/services/background_mqtt_config.dart';
import 'package:e_metrics_iot/src/services/mqtt_credentials_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryCredentialsStore implements MqttCredentialsStore {
  String username = '';
  String password = '';

  @override
  Future<void> clear() async {
    username = '';
    password = '';
  }

  @override
  Future<String> readPassword() async => password;

  @override
  Future<String> readUsername() async => username;

  @override
  Future<void> writeCredentials({
    required String username,
    required String password,
  }) async {
    this.username = username;
    this.password = password;
  }
}

void main() {
  group('BackgroundMqttConfig', () {
    test('usa valores padrão quando prefs estão vazias', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final credentialsStore = _InMemoryCredentialsStore();

      final config = await BackgroundMqttConfig.fromStorage(
        prefs,
        credentialsStore,
      );

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
        'mqtt_topic': 'energia/medidor',
        'mqtt_request_topic': 'energia/medidor/history/request',
        'mqtt_use_tls': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final credentialsStore = _InMemoryCredentialsStore()
        ..username = 'energia'
        ..password = 'segredo';

      final config = await BackgroundMqttConfig.fromStorage(
        prefs,
        credentialsStore,
      );

      expect(config.broker, 'broker.hivemq.com');
      expect(config.port, 8883);
      expect(config.clientId, 'client_123');
      expect(config.username, 'energia');
      expect(config.password, 'segredo');
      expect(config.topic, 'energia/medidor');
      expect(config.requestTopic, 'energia/medidor/history/request');
      expect(config.useTls, isTrue);
    });

    test('migra credenciais legadas do shared preferences', () async {
      SharedPreferences.setMockInitialValues({
        'mqtt_username': 'legacy_user',
        'mqtt_password': 'legacy_pass',
      });
      final prefs = await SharedPreferences.getInstance();
      final credentialsStore = _InMemoryCredentialsStore();

      final config = await BackgroundMqttConfig.fromStorage(
        prefs,
        credentialsStore,
      );

      expect(config.username, 'legacy_user');
      expect(config.password, 'legacy_pass');
      expect(credentialsStore.username, 'legacy_user');
      expect(credentialsStore.password, 'legacy_pass');
      expect(prefs.getString('mqtt_username'), isNull);
      expect(prefs.getString('mqtt_password'), isNull);
    });

    test('identifica quando o perfil de conexao MQTT muda', () {
      const base = BackgroundMqttConfig(
        broker: 'broker.local',
        port: 1883,
        clientId: 'client_a',
        username: 'user',
        password: 'pass',
        topic: 'energia/a',
        requestTopic: 'energia/a/history/request',
        useTls: false,
      );
      const same = BackgroundMqttConfig(
        broker: 'broker.local',
        port: 1883,
        clientId: 'client_a',
        username: 'user',
        password: 'pass',
        topic: 'energia/a',
        requestTopic: 'energia/a/history/request',
        useTls: false,
      );
      const changed = BackgroundMqttConfig(
        broker: 'broker.local',
        port: 8883,
        clientId: 'client_a',
        username: 'user',
        password: 'pass',
        topic: 'energia/a',
        requestTopic: 'energia/a/history/request',
        useTls: true,
      );

      expect(base.sameConnectionProfile(same), isTrue);
      expect(base.sameConnectionProfile(changed), isFalse);
    });
  });
}
