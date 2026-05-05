import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_status_provider.dart';
import 'package:e_metrics_iot/src/data/metric_model.dart';
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

  testWidgets(
    'não marca medidor como ativo com leitura anterior à conexão atual',
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

      await tester.longPress(find.byIcon(Icons.sensors).first);
      await tester.pumpAndSettle();

      expect(
        find.text('Dispositivo conectado, sem leituras após a conexão.'),
        findsOneWidget,
      );
      expect(find.text('Comunicação com dispositivo ativa.'), findsNothing);
    },
  );
}
