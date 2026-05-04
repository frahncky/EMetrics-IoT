import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_status_provider.dart';
import 'package:e_metrics_iot/src/ui/shared/mqtt_connection_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('abre dialogo central de conexao ao segurar icone MQTT', (
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
}
