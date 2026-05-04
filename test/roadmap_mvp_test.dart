import 'package:e_metrics_iot/src/data/integration_sync_item.dart';
import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/data/metric_repository.dart';
import 'package:e_metrics_iot/src/providers/forecast_provider.dart';
import 'package:e_metrics_iot/src/providers/integration_settings_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_settings_provider.dart';
import 'package:e_metrics_iot/src/services/integration_service.dart';
import 'package:e_metrics_iot/src/services/mqtt_credentials_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryCredentialsStore implements MqttCredentialsStore {
  String defaultUsername = '';
  String defaultPassword = '';
  final Map<String, String> usernames = {};
  final Map<String, String> passwords = {};

  @override
  Future<void> clear() async {
    defaultUsername = '';
    defaultPassword = '';
  }

  @override
  Future<void> clearProfile(String profileId) async {
    usernames.remove(profileId);
    passwords.remove(profileId);
  }

  @override
  Future<String> readPassword() async => defaultPassword;

  @override
  Future<String> readPasswordForProfile(String profileId) async =>
      passwords[profileId] ?? '';

  @override
  Future<String> readUsername() async => defaultUsername;

  @override
  Future<String> readUsernameForProfile(String profileId) async =>
      usernames[profileId] ?? '';

  @override
  Future<void> writeCredentials({
    required String username,
    required String password,
  }) async {
    defaultUsername = username;
    defaultPassword = password;
  }

  @override
  Future<void> writeCredentialsForProfile({
    required String profileId,
    required String username,
    required String password,
  }) async {
    usernames[profileId] = username;
    passwords[profileId] = password;
  }
}

class _MemoryMetricRepository extends MetricRepository {
  final List<IntegrationSyncItem> pending = [];
  int _nextId = 1;

  @override
  Future<void> enqueueMetricSync(Metric metric, {String? profileId}) async {
    pending.add(
      IntegrationSyncItem(
        id: _nextId++,
        createdAt: DateTime(2026, 5, 3),
        metricTimestamp: metric.timestamp,
        payload: '{"timestamp":${metric.timestamp.millisecondsSinceEpoch},"power":${metric.power}}',
        profileId: profileId,
        attempts: 0,
        lastError: null,
      ),
    );
  }

  @override
  Future<List<IntegrationSyncItem>> getPendingMetricSyncItems({int limit = 50}) async {
    return pending.take(limit).toList();
  }

  @override
  Future<void> markMetricSyncFailed(int id, String error) async {
    final index = pending.indexWhere((item) => item.id == id);
    if (index >= 0) {
      final item = pending[index];
      pending[index] = IntegrationSyncItem(
        id: item.id,
        createdAt: item.createdAt,
        metricTimestamp: item.metricTimestamp,
        payload: item.payload,
        profileId: item.profileId,
        attempts: item.attempts + 1,
        lastError: error,
      );
    }
  }

  @override
  Future<void> markMetricSyncSucceeded(List<int> ids) async {
    pending.removeWhere((item) => ids.contains(item.id));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mqttSettingsProvider gerencia perfis e alterna perfil ativo', () async {
    final store = _MemoryCredentialsStore();
    final notifier = MqttSettingsNotifier(store);
    addTearDown(notifier.dispose);

    final initial = await notifier.load();
    expect(initial.profileId, 'default');

    await notifier.update(
      broker: 'broker-1',
      port: 1883,
      clientId: 'device-a',
      username: 'user-a',
      password: 'pass-a',
      topic: 'a/topic',
      requestTopic: 'a/request',
      useTls: false,
    );
    final created = await notifier.createProfile(name: 'Medidor B');
    await notifier.update(
      broker: 'broker-2',
      port: 1884,
      clientId: 'device-b',
      username: 'user-b',
      password: 'pass-b',
      topic: 'b/topic',
      requestTopic: 'b/request',
      useTls: true,
    );
    final profiles = await notifier.loadProfiles();

    expect(profiles, hasLength(2));
    expect(created.profileName, 'Medidor B');

    final selectedDefault = await notifier.selectProfile('default');
    expect(selectedDefault.broker, 'broker-1');
    expect(selectedDefault.username, 'user-a');

    final selectedCreated = await notifier.selectProfile(created.profileId);
    expect(selectedCreated.broker, 'broker-2');
    expect(selectedCreated.username, 'user-b');
    expect(selectedCreated.useTls, isTrue);
  });

  test('integrationService enfileira falha e limpa fila ao sincronizar', () async {
    final repository = _MemoryMetricRepository();
    final metric = Metric(
      timestamp: DateTime(2026, 5, 3, 12),
      voltage: 220,
      current: 1.2,
      power: 180,
      pf: 0.97,
      frequency: 60,
      energy: 12.3,
    );

    final failingService = IntegrationService(
      repository: repository,
      loadSettings: () async => const IntegrationSettings(
        enabled: true,
        baseUrl: 'https://api.example.com/',
        metricsPath: '/metrics',
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
      client: MockClient((request) async => http.Response('offline', 503)),
    );

    final submit = await failingService.submitMetric(metric, profileId: 'device-a');
    expect(submit.delivered, isFalse);
    expect(submit.queued, isTrue);
    expect(repository.pending, hasLength(1));

    final successService = IntegrationService(
      repository: repository,
      loadSettings: () async => const IntegrationSettings(
        enabled: true,
        baseUrl: 'https://api.example.com/',
        metricsPath: '/metrics',
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

    final flush = await successService.flushPendingQueue();
    expect(flush.deliveredCount, 1);
    expect(flush.failedCount, 0);
    expect(repository.pending, isEmpty);
  });

  test('forecastProvider calcula tendencia com leituras recentes', () {
    final metrics = List<Metric>.generate(6, (index) {
      return Metric(
        timestamp: DateTime(2026, 5, 3, 10, index * 5),
        voltage: 220,
        current: 1.0 + (index * 0.1),
        power: 100 + (index * 12),
        pf: 0.95,
        frequency: 60,
        energy: 5 + (index * 0.2),
      );
    }).reversed.toList();

    final snapshot = buildForecastForMetrics(metrics);

    expect(snapshot, isNotNull);
    expect(snapshot!.projectedPowerWatts, greaterThan(0));
    expect(snapshot.sampleCount, 6);
    expect(snapshot.trendLabel, 'Tendência de alta');
  });
}