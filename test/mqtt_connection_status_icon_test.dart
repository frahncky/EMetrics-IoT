import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_status_provider.dart';
import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/theme/app_colors.dart';
import 'package:e_metrics_iot/src/ui/shared/mqtt_connection_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedMqttStatusNotifier extends MqttStatusNotifier {
  _FixedMqttStatusNotifier(MqttStatusState initial)
    : super(() async => false) {
    state = initial;
  }
}

void main() {
  testWidgets('abre diálogo central de conexão ao segurar ícone MQTT', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metricsProvider.overrideWith((ref) async => []),
          mqttStatusProvider.overrideWith(
            (ref) => MqttStatusNotifier(() async => false),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [MqttConnectionStatusIcon()],
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byIcon(Icons.cloud_off));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Conexão MQTT'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
    expect(find.text('Desconectar'), findsOneWidget);
  });

  testWidgets('mostra conexão MQTT do app com ícone de nuvem', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metricsProvider.overrideWith((ref) async => []),
          mqttStatusProvider.overrideWith(
            (ref) => _FixedMqttStatusNotifier(
              MqttStatusState(
                broker: 'test.mosquitto.org',
                port: 1883,
                topic: 'emetrics/pzem',
                useTls: false,
                phase: MqttConnectionPhase.connected,
                backgroundActive: false,
                lastConnectedAt: DateTime.now(),
                lastMessage: 'Broker MQTT conectado.',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [MqttConnectionStatusIcon()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    expect(find.byIcon(Icons.sensors), findsNothing);
    expect(find.byIcon(Icons.sensors_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.cloud_done));
    await tester.pumpAndSettle();

    expect(find.text('MQTT conectado.'), findsOneWidget);
  });

  testWidgets(
    'não mostra medidor como ativo antes de nova leitura',
    (tester) async {
      final connectedAt = DateTime.now();
      final oldReading = connectedAt.subtract(const Duration(minutes: 1));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            metricsProvider.overrideWith(
              (ref) async => [
                Metric(
                  timestamp: oldReading,
                  voltage: 220,
                  current: 1,
                  power: 220,
                  pf: 0.95,
                  frequency: 60,
                  energy: 1,
                ),
              ],
            ),
            mqttStatusProvider.overrideWith(
              (ref) => _FixedMqttStatusNotifier(
                MqttStatusState(
                  broker: 'test.mosquitto.org',
                  port: 1883,
                  topic: 'emetrics/pzem',
                  useTls: false,
                  phase: MqttConnectionPhase.connected,
                  backgroundActive: false,
                  lastConnectedAt: connectedAt,
                  lastMessage: 'Broker MQTT conectado.',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: const [MqttConnectionStatusIcon()],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.electric_meter), findsNothing);
      final deviceIcon = tester.widget<Icon>(
        find.byIcon(Icons.electric_meter_outlined),
      );
      expect(deviceIcon.color, AppColors.statusIdle);

      await tester.tap(find.byIcon(Icons.electric_meter_outlined));
      await tester.pumpAndSettle();

      expect(
        find.text('Medidor não conectado.'),
        findsOneWidget,
      );
      expect(
        find.text('Medidor conectado com envio/recebimento de dados.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'mostra medidor conectado quando a leitura existe mas está antiga',
    (tester) async {
      final connectedAt = DateTime.now().subtract(const Duration(minutes: 10));
      final staleReading = DateTime.now().subtract(const Duration(minutes: 6));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            metricsProvider.overrideWith(
              (ref) async => [
                Metric(
                  timestamp: staleReading,
                  voltage: 220,
                  current: 1,
                  power: 220,
                  pf: 0.95,
                  frequency: 60,
                  energy: 1,
                ),
              ],
            ),
            mqttStatusProvider.overrideWith(
              (ref) => _FixedMqttStatusNotifier(
                MqttStatusState(
                  broker: 'test.mosquitto.org',
                  port: 1883,
                  topic: 'emetrics/pzem',
                  useTls: false,
                  phase: MqttConnectionPhase.connected,
                  backgroundActive: false,
                  lastConnectedAt: connectedAt,
                  lastMessage: 'Broker MQTT conectado.',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: const [MqttConnectionStatusIcon()],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final deviceIcon = tester.widget<Icon>(
        find.byIcon(Icons.electric_meter),
      );
      expect(deviceIcon.color, AppColors.statusWarning);

      await tester.tap(find.byIcon(Icons.electric_meter));
      await tester.pumpAndSettle();

      expect(find.textContaining('Medidor conectado. Última leitura'), findsOneWidget);
      expect(
        find.text('Medidor conectado com envio/recebimento de dados.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'mostra medidor ativo quando há leitura recente',
    (tester) async {
      final connectedAt = DateTime.now().subtract(const Duration(minutes: 1));
      final recentReading = DateTime.now();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            metricsProvider.overrideWith(
              (ref) async => [
                Metric(
                  timestamp: recentReading,
                  voltage: 220,
                  current: 1,
                  power: 220,
                  pf: 0.95,
                  frequency: 60,
                  energy: 1,
                ),
              ],
            ),
            mqttStatusProvider.overrideWith(
              (ref) => _FixedMqttStatusNotifier(
                MqttStatusState(
                  broker: 'test.mosquitto.org',
                  port: 1883,
                  topic: 'emetrics/pzem',
                  useTls: false,
                  phase: MqttConnectionPhase.connected,
                  backgroundActive: false,
                  lastConnectedAt: connectedAt,
                  lastMessage: 'Broker MQTT conectado.',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: const [MqttConnectionStatusIcon()],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final deviceIcon = tester.widget<Icon>(
        find.byIcon(Icons.electric_meter),
      );
      expect(deviceIcon.color, AppColors.statusSuccess);

      await tester.tap(find.byIcon(Icons.electric_meter));
      await tester.pumpAndSettle();

      expect(
        find.text('Medidor conectado com envio/recebimento de dados.'),
        findsOneWidget,
      );
    },
  );
}
