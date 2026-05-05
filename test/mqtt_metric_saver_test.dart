import 'dart:async';

import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/data/metric_repository.dart';
import 'package:e_metrics_iot/src/providers/integration_settings_provider.dart';
import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_metric_saver.dart';
import 'package:e_metrics_iot/src/providers/mqtt_settings_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_stream_provider.dart';
import 'package:e_metrics_iot/src/services/integration_service.dart';
import 'package:e_metrics_iot/src/services/mqtt_credentials_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mqtt_client/mqtt_client.dart';

class _SpyMetricRepository extends MetricRepository {
  int insertCalls = 0;

  @override
  Future<void> insertMetric(Metric metric) async {
    insertCalls++;
  }
}

class _FakeMqttSettingsNotifier extends MqttSettingsNotifier {
  _FakeMqttSettingsNotifier() : super(_NoopCredentialsStore()) {
    state = const MqttSettings(
      profileId: 'default',
      profileName: 'Dispositivo principal',
      broker: 'broker.local',
      port: 1883,
      clientId: 'app',
      username: '',
      password: '',
      topic: 'emetrics/pzem',
      requestTopic: 'emetrics/pzem/history/request',
      useTls: false,
    );
  }

  @override
  Future<MqttSettings> load() async => state;
}

class _NoopCredentialsStore implements MqttCredentialsStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> clearProfile(String profileId) async {}

  @override
  Future<String> readPassword() async => '';

  @override
  Future<String> readPasswordForProfile(String profileId) async => '';

  @override
  Future<String> readUsername() async => '';

  @override
  Future<String> readUsernameForProfile(String profileId) async => '';

  @override
  Future<void> writeCredentials({required String username, required String password}) async {}

  @override
  Future<void> writeCredentialsForProfile({
    required String profileId,
    required String username,
    required String password,
  }) async {}
}

MqttReceivedMessage<MqttMessage> _buildMessage(String payload) {
  final builder = MqttClientPayloadBuilder()..addString(payload);
  final publish = MqttPublishMessage().toTopic('emetrics/pzem').publishData(builder.payload!);
  return MqttReceivedMessage<MqttMessage>('emetrics/pzem', publish);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mqttMetricSaver não persiste no foreground com background ativo', () async {
    final spyRepo = _SpyMetricRepository();
    final integrationDisabledService = IntegrationService(
      repository: spyRepo,
      loadSettings: () async => const IntegrationSettings(
        enabled: false,
        baseUrl: '',
        metricsPath: '/api/metrics',
        apiKey: '',
        oauthEnabled: false,
        oauthClientId: '',
        oauthScope: '',
        oauthDeviceEndpoint: '',
        oauthTokenEndpoint: '',
        oauthAccessToken: '',
        oauthTokenType: 'Bearer',
        oauthExpiresAt: null,
      ),
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    final controller = StreamController<List<MqttReceivedMessage<MqttMessage>>>();
    final message = _buildMessage(
      '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,"frequency":60,"energy":1.23}',
    );

    final container = ProviderContainer(
      overrides: [
        metricRepositoryProvider.overrideWithValue(spyRepo),
        mqttStreamProvider.overrideWith((ref) => controller.stream),
        backgroundRunningCheckProvider.overrideWithValue(() async => true),
        mqttSettingsProvider.overrideWith((ref) => _FakeMqttSettingsNotifier()),
        integrationServiceProvider.overrideWithValue(integrationDisabledService),
      ],
    );
    addTearDown(controller.close);
    addTearDown(container.dispose);

    final saverSub = container.listen(mqttMetricSaverProvider, (previous, next) {});
    addTearDown(saverSub.close);
    controller.add([message]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(spyRepo.insertCalls, 0);
  });

  test('mqttMetricSaver persiste no foreground com background inativo', () async {
    final spyRepo = _SpyMetricRepository();
    final integrationDisabledService = IntegrationService(
      repository: spyRepo,
      loadSettings: () async => const IntegrationSettings(
        enabled: false,
        baseUrl: '',
        metricsPath: '/api/metrics',
        apiKey: '',
        oauthEnabled: false,
        oauthClientId: '',
        oauthScope: '',
        oauthDeviceEndpoint: '',
        oauthTokenEndpoint: '',
        oauthAccessToken: '',
        oauthTokenType: 'Bearer',
        oauthExpiresAt: null,
      ),
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    final controller = StreamController<List<MqttReceivedMessage<MqttMessage>>>();
    final message = _buildMessage(
      '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,"frequency":60,"energy":1.23}',
    );

    final container = ProviderContainer(
      overrides: [
        metricRepositoryProvider.overrideWithValue(spyRepo),
        mqttStreamProvider.overrideWith((ref) => controller.stream),
        backgroundRunningCheckProvider.overrideWithValue(() async => false),
        mqttSettingsProvider.overrideWith((ref) => _FakeMqttSettingsNotifier()),
        integrationServiceProvider.overrideWithValue(integrationDisabledService),
      ],
    );
    addTearDown(controller.close);
    addTearDown(container.dispose);

    final saverSub = container.listen(mqttMetricSaverProvider, (previous, next) {});
    addTearDown(saverSub.close);
    controller.add([message]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(spyRepo.insertCalls, 1);
  });
}
