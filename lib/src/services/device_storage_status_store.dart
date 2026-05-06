import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceStorageStatus {
  final bool? sdAvailable;
  final bool? usingSd;
  final double? sdUsagePercent;
  final int? sdUsedBytes;
  final int? sdTotalBytes;
  final DateTime? updatedAt;

  const DeviceStorageStatus({
    this.sdAvailable,
    this.usingSd,
    this.sdUsagePercent,
    this.sdUsedBytes,
    this.sdTotalBytes,
    this.updatedAt,
  });

  const DeviceStorageStatus.empty()
    : sdAvailable = null,
      usingSd = null,
      sdUsagePercent = null,
      sdUsedBytes = null,
      sdTotalBytes = null,
      updatedAt = null;

  bool get hasTelemetry =>
      sdAvailable != null ||
      usingSd != null ||
      sdUsagePercent != null ||
      sdUsedBytes != null ||
      sdTotalBytes != null;
}

class DeviceStorageStatusStore {
  static const _sdAvailableKey = 'device_storage_sd_available';
  static const _usingSdKey = 'device_storage_using_sd';
  static const _usagePercentKey = 'device_storage_sd_usage_percent';
  static const _usedBytesKey = 'device_storage_sd_used_bytes';
  static const _totalBytesKey = 'device_storage_sd_total_bytes';
  static const _updatedAtKey = 'device_storage_updated_at';

  const DeviceStorageStatusStore();

  Future<DeviceStorageStatus> load() async {
    final prefs = await SharedPreferences.getInstance();
    final updatedAtMillis = prefs.getInt(_updatedAtKey);
    return DeviceStorageStatus(
      sdAvailable: prefs.containsKey(_sdAvailableKey)
          ? prefs.getBool(_sdAvailableKey)
          : null,
      usingSd: prefs.containsKey(_usingSdKey)
          ? prefs.getBool(_usingSdKey)
          : null,
      sdUsagePercent: prefs.getDouble(_usagePercentKey),
      sdUsedBytes: prefs.getInt(_usedBytesKey),
      sdTotalBytes: prefs.getInt(_totalBytesKey),
      updatedAt: updatedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtMillis)
          : null,
    );
  }

  Future<void> save(DeviceStorageStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await _setNullableBool(prefs, _sdAvailableKey, status.sdAvailable);
    await _setNullableBool(prefs, _usingSdKey, status.usingSd);
    await _setNullableDouble(prefs, _usagePercentKey, status.sdUsagePercent);
    await _setNullableInt(prefs, _usedBytesKey, status.sdUsedBytes);
    await _setNullableInt(prefs, _totalBytesKey, status.sdTotalBytes);
    await _setNullableInt(
      prefs,
      _updatedAtKey,
      status.updatedAt?.millisecondsSinceEpoch,
    );
  }

  Future<void> _setNullableBool(
    SharedPreferences prefs,
    String key,
    bool? value,
  ) {
    if (value == null) {
      return prefs.remove(key);
    }
    return prefs.setBool(key, value);
  }

  Future<void> _setNullableDouble(
    SharedPreferences prefs,
    String key,
    double? value,
  ) {
    if (value == null) {
      return prefs.remove(key);
    }
    return prefs.setDouble(key, value);
  }

  Future<void> _setNullableInt(
    SharedPreferences prefs,
    String key,
    int? value,
  ) {
    if (value == null) {
      return prefs.remove(key);
    }
    return prefs.setInt(key, value);
  }
}

DeviceStorageStatus? parseDeviceStorageStatusFromMqtt(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final nestedStorage = decoded['storage'];
    final storage = nestedStorage is Map<String, dynamic>
        ? nestedStorage
        : const <String, dynamic>{};

    final sdAvailable =
        _readBool(storage, 'sdAvailable') ??
        _readBool(decoded, 'sdAvailable') ??
        _readBool(storage, 'available') ??
        _readBool(decoded, 'sdCardAvailable');
    final usingSd =
        _readBool(storage, 'usingSd') ??
        _readBool(decoded, 'usingSd') ??
        _readBool(storage, 'sd') ??
        _readBool(decoded, 'storageUsesSd');
    final usedBytes =
        _readInt(storage, 'sdUsedBytes') ??
        _readInt(decoded, 'sdUsedBytes') ??
        _readInt(storage, 'usedBytes') ??
        _readInt(decoded, 'sdCardUsedBytes');
    final totalBytes =
        _readInt(storage, 'sdTotalBytes') ??
        _readInt(decoded, 'sdTotalBytes') ??
        _readInt(storage, 'totalBytes') ??
        _readInt(decoded, 'sdCardTotalBytes');
    final rawPercent =
        _readDouble(storage, 'sdUsagePercent') ??
        _readDouble(decoded, 'sdUsagePercent') ??
        _readDouble(storage, 'usedPercent') ??
        _readDouble(decoded, 'sdUsedPercent') ??
        _percentFromBytes(usedBytes, totalBytes);
    final usagePercent = rawPercent?.clamp(0, 100).toDouble();

    final status = DeviceStorageStatus(
      sdAvailable: sdAvailable,
      usingSd: usingSd,
      sdUsagePercent: usagePercent,
      sdUsedBytes: usedBytes,
      sdTotalBytes: totalBytes,
      updatedAt: DateTime.now(),
    );

    return status.hasTelemetry ? status : null;
  } catch (_) {
    return null;
  }
}

bool? _readBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return null;
}

int? _readInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _readDouble(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
}

double? _percentFromBytes(int? usedBytes, int? totalBytes) {
  if (usedBytes == null || totalBytes == null || totalBytes <= 0) {
    return null;
  }
  return usedBytes * 100 / totalBytes;
}
