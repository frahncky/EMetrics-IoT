import 'package:shared_preferences/shared_preferences.dart';

class StorageSettings {
  final int localRetentionDays;
  final int deviceRetentionDays;

  const StorageSettings({
    required this.localRetentionDays,
    required this.deviceRetentionDays,
  });

  StorageSettings copyWith({
    int? localRetentionDays,
    int? deviceRetentionDays,
  }) {
    return StorageSettings(
      localRetentionDays: localRetentionDays ?? this.localRetentionDays,
      deviceRetentionDays: deviceRetentionDays ?? this.deviceRetentionDays,
    );
  }
}

class StorageSettingsStore {
  static const localRetentionDaysKey = 'storage_local_retention_days';
  static const deviceRetentionDaysKey = 'storage_device_retention_days';
  static const defaultLocalRetentionDays = 30;
  static const defaultDeviceRetentionDays = 30;
  static const minRetentionDays = 1;
  static const maxRetentionDays = 3650;

  const StorageSettingsStore();

  Future<StorageSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageSettings(
      localRetentionDays: normalizeRetentionDays(
        prefs.getInt(localRetentionDaysKey) ?? defaultLocalRetentionDays,
      ),
      deviceRetentionDays: normalizeRetentionDays(
        prefs.getInt(deviceRetentionDaysKey) ?? defaultDeviceRetentionDays,
      ),
    );
  }

  Future<void> save(StorageSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      localRetentionDaysKey,
      normalizeRetentionDays(settings.localRetentionDays),
    );
    await prefs.setInt(
      deviceRetentionDaysKey,
      normalizeRetentionDays(settings.deviceRetentionDays),
    );
  }

  static int normalizeRetentionDays(int value) {
    if (value < minRetentionDays) {
      return minRetentionDays;
    }
    if (value > maxRetentionDays) {
      return maxRetentionDays;
    }
    return value;
  }
}
