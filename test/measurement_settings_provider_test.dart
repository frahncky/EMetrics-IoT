import 'package:e_metrics_iot/src/providers/measurement_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MeasurementSettingsNotifier', () {
    test('carrega valores padrão quando não há preferências', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = await container
          .read(measurementSettingsProvider.notifier)
          .load();

      expect(settings.voltageMin, 200);
      expect(settings.voltageMax, 240);
      expect(settings.energyLimitKwh, 10);
      expect(settings.tariffPerKwh, 0);
    });

    test('atualiza e persiste configurações de medição', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(measurementSettingsProvider.notifier)
          .update(
            voltageMin: 210,
            voltageMax: 235,
            energyLimitKwh: 15,
            tariffPerKwh: 0.92,
          );

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);

      final settings = await reloaded
          .read(measurementSettingsProvider.notifier)
          .load();

      expect(settings.voltageMin, 210);
      expect(settings.voltageMax, 235);
      expect(settings.energyLimitKwh, 15);
      expect(settings.tariffPerKwh, 0.92);
    });
  });
}
