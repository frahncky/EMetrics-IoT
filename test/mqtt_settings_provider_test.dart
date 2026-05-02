import 'package:e_metrics_iot/src/providers/mqtt_settings_provider.dart';
import 'package:e_metrics_iot/src/services/mqtt_credentials_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  group('MqttSettingsNotifier', () {
    test('carrega valores padrão com porta e TLS desativado', () async {
      SharedPreferences.setMockInitialValues({});
      final credentialsStore = _InMemoryCredentialsStore();
      final container = ProviderContainer(
        overrides: [
          mqttCredentialsStoreProvider.overrideWithValue(credentialsStore),
        ],
      );
      addTearDown(container.dispose);

      final settings = await container.read(mqttSettingsProvider.notifier).load();

      expect(settings.broker, 'test.mosquitto.org');
      expect(settings.port, 1883);
      expect(settings.clientId, 'emetrics_app');
      expect(settings.username, '');
      expect(settings.password, '');
      expect(settings.topic, 'emetrics/pzem');
      expect(settings.requestTopic, 'emetrics/pzem/history/request');
      expect(settings.useTls, isFalse);
    });

    test('persiste credenciais, porta e TLS', () async {
      SharedPreferences.setMockInitialValues({});
      final credentialsStore = _InMemoryCredentialsStore();
      final container = ProviderContainer(
        overrides: [
          mqttCredentialsStoreProvider.overrideWithValue(credentialsStore),
        ],
      );
      addTearDown(container.dispose);

      await container.read(mqttSettingsProvider.notifier).update(
        broker: 'broker.local',
        port: 8883,
        clientId: 'medidor_app',
        username: 'user01',
        password: 'senha01',
        topic: 'energia/dispositivo01',
        requestTopic: 'energia/dispositivo01/history/request',
        useTls: true,
      );

      final reloaded = ProviderContainer(
        overrides: [
          mqttCredentialsStoreProvider.overrideWithValue(credentialsStore),
        ],
      );
      addTearDown(reloaded.dispose);

      final settings = await reloaded.read(mqttSettingsProvider.notifier).load();

      expect(settings.broker, 'broker.local');
      expect(settings.port, 8883);
      expect(settings.clientId, 'medidor_app');
      expect(settings.username, 'user01');
      expect(settings.password, 'senha01');
      expect(settings.topic, 'energia/dispositivo01');
      expect(settings.requestTopic, 'energia/dispositivo01/history/request');
      expect(settings.useTls, isTrue);
      expect(credentialsStore.username, 'user01');
      expect(credentialsStore.password, 'senha01');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mqtt_username'), isNull);
      expect(prefs.getString('mqtt_password'), isNull);
    });
  });
}