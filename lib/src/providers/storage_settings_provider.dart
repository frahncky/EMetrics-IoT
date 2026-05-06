import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_settings_store.dart';

final storageSettingsStoreProvider = Provider<StorageSettingsStore>(
  (ref) => const StorageSettingsStore(),
);

class StorageSettingsNotifier extends StateNotifier<StorageSettings> {
  final StorageSettingsStore _store;

  StorageSettingsNotifier(this._store)
    : super(
        const StorageSettings(
          localRetentionDays: StorageSettingsStore.defaultLocalRetentionDays,
          deviceRetentionDays: StorageSettingsStore.defaultDeviceRetentionDays,
        ),
      ) {
    load();
  }

  Future<StorageSettings> load() async {
    state = await _store.load();
    return state;
  }

  Future<StorageSettings> update({
    required int localRetentionDays,
    required int deviceRetentionDays,
  }) async {
    state = StorageSettings(
      localRetentionDays: StorageSettingsStore.normalizeRetentionDays(
        localRetentionDays,
      ),
      deviceRetentionDays: StorageSettingsStore.normalizeRetentionDays(
        deviceRetentionDays,
      ),
    );
    await _store.save(state);
    return state;
  }
}

final storageSettingsProvider =
    StateNotifierProvider<StorageSettingsNotifier, StorageSettings>(
      (ref) => StorageSettingsNotifier(ref.watch(storageSettingsStoreProvider)),
    );
