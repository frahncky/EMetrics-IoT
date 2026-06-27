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

List<Override> _baseOverrides({
  Future<List<Metric>> Function()? metricsFactory,
  Metric? latestMetric,
}) {
  return [
    metricsProvider.overrideWith(
      (ref) => metricsFactory != null ? metricsFactory() : Future.value([]),
    ),
    if (latestMetric != null)
      latestMqttMetricProvider.overrideWith((ref) => latestMetric),
    mqttMetricSaverProvider.overrideWith((ref) {}),
    mqttSettingsProvider.overrideWith((ref) => _TestMqttSettingsNotifier()),
    mqttStatusProvider.overrideWith(
      (ref) => MqttStatusNotifier(() async => false),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'mantém a organização do dashboard enquanto a primeira métrica carrega',
    (tester) async {
      final metricsCompleter = Completer<List<Metric>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            metricsFactory: () => metricsCompleter.future,
          ),
          child: const MaterialApp(home: DashboardPage()),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(DashboardTabs), findsOneWidget);
      expect(find.text('Aguardando dados'), findsNWidgets(2));
    },
  );

  testWidgets('exibe 8 cards de indicadores com o layout padrão', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(),
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pump();

    // Layout padrão tem 8 slots (energy_apparent, power, energy_reactive, pf,
    // voltage, current, energy, frequency).
    for (var i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey('slot_$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('slot_8')), findsNothing);
  });

  testWidgets('mostra valor de tensão quando métrica chega via provider', (
    tester,
  ) async {
    final metric = Metric(
      timestamp: DateTime.now(),
      voltage: 220.5,
      current: 1.2,
      power: 250.0,
      pf: 0.95,
      frequency: 60.0,
      energy: 0.5,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(
          metricsFactory: () async => [metric],
          latestMetric: metric,
        ),
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Tensão com fractionDigits=1 → '220.5'
    expect(find.text('220.5'), findsOneWidget);
  });

  testWidgets(
    'diálogo de confirmação aparece ao tocar no botão de reset de energia',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const MaterialApp(home: DashboardPage()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Zerar energia acumulada'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Zerar'), findsOneWidget);
    },
  );

  testWidgets('cancelar no diálogo de reset fecha sem executar ação', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(),
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    // Botão de reset volta a ficar disponível (não está em estado de loading).
    expect(find.byIcon(Icons.restart_alt), findsOneWidget);
  });

  testWidgets('seletor de grandeza abre ao segurar um card de indicador', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(),
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey('slot_0')));
    await tester.pumpAndSettle();

    expect(find.text('Escolher grandeza'), findsOneWidget);
  });
}
