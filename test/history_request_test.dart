import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_status_provider.dart';
import 'package:e_metrics_iot/src/services/mqtt_service.dart';
import 'package:e_metrics_iot/src/ui/history/history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingMqttService extends MqttService {
  _FailingMqttService() : super(broker: 'test.mosquitto.org', clientId: 'test', topic: 't');

  @override
  Future<void> requestHistory({required DateTime from, required DateTime to}) async {
    throw const MqttServiceException('erro de teste');
  }
}

class _FakeMqttStatusNotifier extends MqttStatusNotifier {
  _FakeMqttStatusNotifier({required bool backgroundActive})
      : super(() async => backgroundActive) {
    if (backgroundActive) {
      setBackgroundActive(true);
      markConnected();
    }
  }
}

void main() {
  testWidgets('HistoryPage exibe feedback quando solicitacao de historico falha', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mqttServiceProvider.overrideWith((ref) => _FailingMqttService()),
          metricsByRangeProvider.overrideWith((ref, query) async => const []),
        ],
        child: const MaterialApp(home: HistoryPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Solicitar do medidor'), findsOneWidget);
    await tester.tap(find.text('Solicitar do medidor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Falha ao solicitar histórico'), findsOneWidget);
  });

  testWidgets('HistoryPage usa o handler de segundo plano quando ativo', (
    WidgetTester tester,
  ) async {
    var called = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mqttStatusProvider.overrideWith(
            (ref) => _FakeMqttStatusNotifier(backgroundActive: true),
          ),
          backgroundHistoryRequestProvider.overrideWithValue(({
            required DateTime from,
            required DateTime to,
          }) async {
            called = true;
            throw const MqttServiceException('erro em segundo plano');
          }),
          metricsByRangeProvider.overrideWith((ref, query) async => const []),
        ],
        child: const MaterialApp(home: HistoryPage()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar do medidor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(called, isTrue);
    expect(find.textContaining('Falha ao solicitar histórico'), findsOneWidget);
  });
}
