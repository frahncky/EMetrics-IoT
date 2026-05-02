import 'package:e_metrics_iot/src/providers/alert_history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AlertHistoryNotifier', () {
    test('adiciona, reconhece e limpa alertas', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(alertHistoryProvider.notifier);
      final alert = AlertRecord(
        id: 'voltage_1',
        title: 'Tensão fora da faixa',
        message: 'Valor: 250.00 V',
        type: 'voltage',
        severity: AlertSeverity.warning,
        createdAt: DateTime(2026, 5, 1, 10, 30),
      );

      await notifier.add(alert);
      expect(container.read(alertHistoryProvider), hasLength(1));
      expect(container.read(alertHistoryProvider).first.acknowledged, isFalse);

      await notifier.acknowledge(alert.id);
      expect(container.read(alertHistoryProvider).first.acknowledged, isTrue);

      await notifier.clear();
      expect(container.read(alertHistoryProvider), isEmpty);
    });

    test('recarrega alertas persistidos', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(alertHistoryProvider.notifier).add(
        AlertRecord(
          id: 'energy_1',
          title: 'Consumo excessivo',
          message: 'Energia acumulada: 12.50 kWh',
          type: 'energy',
          severity: AlertSeverity.critical,
          createdAt: DateTime(2026, 5, 1, 11, 0),
        ),
      );

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      await reloaded.read(alertHistoryProvider.notifier).load();

      final alerts = reloaded.read(alertHistoryProvider);
      expect(alerts, hasLength(1));
      expect(alerts.first.title, 'Consumo excessivo');
      expect(alerts.first.severity, AlertSeverity.critical);
    });
  });
}