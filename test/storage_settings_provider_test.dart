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
    });

    test('atualiza e persiste retenções', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(storageSettingsProvider.notifier)
          .update(localRetentionDays: 14, deviceRetentionDays: 60);

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);

      final settings = await reloaded
          .read(storageSettingsProvider.notifier)
          .load();

      expect(settings.localRetentionDays, 14);
      expect(settings.deviceRetentionDays, 60);
    });
  });
}
