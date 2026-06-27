import 'package:e_metrics_iot/src/providers/storage_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageSettingsNotifier', () {
    test('carrega valores padrão quando não há preferências', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = await container
          .read(storageSettingsProvider.notifier)
          .load();

      expect(settings.localRetentionDays, 30);
      expect(settings.deviceRetentionDays, 30);
      expect(settings.measurementIntervalMs, 2000);
      expect(settings.sdLogIntervalMs, 2000);
      expect(settings.mqttPublishIntervalMs, 2000);
    });

    test('atualiza e persiste retenções e intervalos', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(storageSettingsProvider.notifier)
          .update(
            localRetentionDays: 14,
            deviceRetentionDays: 60,
            measurementIntervalMs: 1000,
            sdLogIntervalMs: 1500,
            mqttPublishIntervalMs: 5000,
          );

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);

      final settings = await reloaded
          .read(storageSettingsProvider.notifier)
          .load();

      expect(settings.localRetentionDays, 14);
      expect(settings.deviceRetentionDays, 60);
      expect(settings.measurementIntervalMs, 1000);
      expect(settings.sdLogIntervalMs, 1500);
      expect(settings.mqttPublishIntervalMs, 5000);
    });

    test('normaliza intervalos fora da faixa permitida', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = await container
          .read(storageSettingsProvider.notifier)
          .update(
            localRetentionDays: 30,
            deviceRetentionDays: 30,
            measurementIntervalMs: 50,
            sdLogIntervalMs: 120000,
            mqttPublishIntervalMs: 2000,
          );

      expect(settings.measurementIntervalMs, 100);
      expect(settings.sdLogIntervalMs, 60000);
      expect(settings.mqttPublishIntervalMs, 2000);
    });
  });
}
