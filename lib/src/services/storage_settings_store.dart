import 'package:shared_preferences/shared_preferences.dart';

class StorageSettings {
  final int localRetentionDays;
  final int deviceRetentionDays;
  final int measurementIntervalMs;
  final int sdLogIntervalMs;
  final int mqttPublishIntervalMs;

  const StorageSettings({
    required this.localRetentionDays,
    required this.deviceRetentionDays,
    required this.measurementIntervalMs,
    required this.sdLogIntervalMs,
    required this.mqttPublishIntervalMs,
  });

  StorageSettings copyWith({
    int? localRetentionDays,
    int? deviceRetentionDays,
    int? measurementIntervalMs,
    int? sdLogIntervalMs,
    int? mqttPublishIntervalMs,
  }) {
    return StorageSettings(
      localRetentionDays: localRetentionDays ?? this.localRetentionDays,
      deviceRetentionDays: deviceRetentionDays ?? this.deviceRetentionDays,
      measurementIntervalMs:
          measurementIntervalMs ?? this.measurementIntervalMs,
      sdLogIntervalMs: sdLogIntervalMs ?? this.sdLogIntervalMs,
      mqttPublishIntervalMs:
          mqttPublishIntervalMs ?? this.mqttPublishIntervalMs,
    );
  }
}

class StorageSettingsStore {
  static const localRetentionDaysKey = 'storage_local_retention_days';
  static const deviceRetentionDaysKey = 'storage_device_retention_days';
  static const measurementIntervalMsKey = 'storage_measurement_interval_ms';
  static const sdLogIntervalMsKey = 'storage_sd_log_interval_ms';
  static const mqttPublishIntervalMsKey = 'storage_mqtt_publish_interval_ms';
  static const defaultLocalRetentionDays = 30;
  static const defaultDeviceRetentionDays = 30;
  static const defaultMeasurementIntervalMs = 2000;
  static const defaultSdLogIntervalMs = 2000;
  static const defaultMqttPublishIntervalMs = 2000;
  static const minRetentionDays = 1;
  static const maxRetentionDays = 3650;
  static const minTelemetryIntervalMs = 100;
  static const maxTelemetryIntervalMs = 60000;

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
      measurementIntervalMs: normalizeTelemetryIntervalMs(
        prefs.getInt(measurementIntervalMsKey) ?? defaultMeasurementIntervalMs,
      ),
      sdLogIntervalMs: normalizeTelemetryIntervalMs(
        prefs.getInt(sdLogIntervalMsKey) ?? defaultSdLogIntervalMs,
      ),
      mqttPublishIntervalMs: normalizeTelemetryIntervalMs(
        prefs.getInt(mqttPublishIntervalMsKey) ?? defaultMqttPublishIntervalMs,
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
    await prefs.setInt(
      measurementIntervalMsKey,
      normalizeTelemetryIntervalMs(settings.measurementIntervalMs),
    );
    await prefs.setInt(
      sdLogIntervalMsKey,
      normalizeTelemetryIntervalMs(settings.sdLogIntervalMs),
    );
    await prefs.setInt(
      mqttPublishIntervalMsKey,
      normalizeTelemetryIntervalMs(settings.mqttPublishIntervalMs),
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

  static int normalizeTelemetryIntervalMs(int value) {
    if (value < minTelemetryIntervalMs) {
      return minTelemetryIntervalMs;
    }
    if (value > maxTelemetryIntervalMs) {
      return maxTelemetryIntervalMs;
    }
    return value;
  }
}
