import 'package:e_metrics_iot/src/providers/mqtt_settings_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_status_provider.dart';
import 'package:e_metrics_iot/src/services/mqtt_credentials_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryCredentialsStore implements MqttCredentialsStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String> readPassword() async => '';

  @override
  Future<String> readUsername() async => '';

  @override
  Future<void> writeCredentials({
    required String username,
    required String password,
  }) async {}
}

class _FakeMqttSettingsNotifier extends MqttSettingsNotifier {
  _FakeMqttSettingsNotifier() : super(_InMemoryCredentialsStore()) {
    state = const MqttSettings(
      broker: 'broker.local',
      port: 8883,
      clientId: 'cliente_01',
      username: 'user',
      password: 'senha',
      topic: 'energia/casa',
      requestTopic: 'energia/casa/history/request',
      useTls: true,
    );
  }

  @override
  Future<MqttSettings> load() async {
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MqttStatusNotifier', () {
    test('configura status a partir das configurações e atualiza fases', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          mqttSettingsProvider.overrideWith((ref) => _FakeMqttSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(mqttStatusProvider.notifier);
      notifier.markConnecting();
      notifier.markConnected();
      notifier.setBackgroundActive(true);

      final status = container.read(mqttStatusProvider);
      expect(status.broker, 'broker.local');
      expect(status.port, 8883);
      expect(status.topic, 'energia/casa');
      expect(status.useTls, isTrue);
      expect(status.phase, MqttConnectionPhase.connected);
      expect(status.backgroundActive, isTrue);
      expect(status.lastMessage, 'Broker MQTT conectado.');
      expect(status.lastConnectedAt, isNotNull);
    });

    test('marca erro e desconexão com mensagem amigável', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          mqttCredentialsStoreProvider.overrideWithValue(
            _InMemoryCredentialsStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(mqttStatusProvider.notifier);
      notifier.markError('Falha ao conectar.');
      expect(container.read(mqttStatusProvider).phase, MqttConnectionPhase.error);

      notifier.markDisconnected('Broker MQTT desconectado.');
      final status = container.read(mqttStatusProvider);
      expect(status.phase, MqttConnectionPhase.disconnected);
      expect(status.lastMessage, 'Broker MQTT desconectado.');
    });
  });
}