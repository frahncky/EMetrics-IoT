import 'dart:async';

import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_metric_saver.dart';
import 'package:e_metrics_iot/src/providers/mqtt_settings_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_status_provider.dart';
import 'package:e_metrics_iot/src/services/mqtt_credentials_store.dart';
import 'package:e_metrics_iot/src/ui/dashboard/dashboard_page.dart';
import 'package:e_metrics_iot/src/ui/dashboard/dashboard_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestMqttSettingsNotifier extends MqttSettingsNotifier {
  _TestMqttSettingsNotifier() : super(_NoopCredentialsStore()) {
    state = const MqttSettings(
      profileId: 'default',
      profileName: 'Dispositivo de teste',
      broker: 'broker.local',
      port: 1883,
      clientId: 'emetrics_test',
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
  Future<void> writeCredentials({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> writeCredentialsForProfile({
    required String profileId,
    required String username,
    required String password,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mantém a organização do dashboard enquanto a primeira métrica carrega',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final metricsCompleter = Completer<List<Metric>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            metricsProvider.overrideWith((ref) => metricsCompleter.future),
            mqttMetricSaverProvider.overrideWith((ref) {}),
            mqttSettingsProvider.overrideWith(
              (ref) => _TestMqttSettingsNotifier(),
            ),
            mqttStatusProvider.overrideWith(
              (ref) => MqttStatusNotifier(() async => false),
            ),
          ],
          child: const MaterialApp(home: DashboardPage()),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(DashboardTabs), findsOneWidget);
      expect(find.text('Aparente'), findsOneWidget);
      expect(find.text('Aguardando dados'), findsNWidgets(2));
    },
  );
}
