import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../services/device_storage_status_store.dart';
import 'mqtt_stream_provider.dart';

final deviceStorageStatusStoreProvider = Provider<DeviceStorageStatusStore>(
  (ref) => const DeviceStorageStatusStore(),
);

class DeviceStorageNotifier extends StateNotifier<DeviceStorageStatus> {
  final DeviceStorageStatusStore _store;

  DeviceStorageNotifier(this._store)
    : super(const DeviceStorageStatus.empty()) {
    load();
  }

  Future<DeviceStorageStatus> load() async {
    state = await _store.load();
    return state;
  }

  Future<void> update(DeviceStorageStatus status) async {
    state = status;
    await _store.save(status);
  }

  Future<void> updateFromPayload(String payload) async {
    final status = parseDeviceStorageStatusFromMqtt(payload);
    if (status == null) {
      return;
    }
    await update(status);
  }
}

final deviceStorageProvider =
    StateNotifierProvider<DeviceStorageNotifier, DeviceStorageStatus>(
      (ref) =>
          DeviceStorageNotifier(ref.watch(deviceStorageStatusStoreProvider)),
    );

final deviceStorageTrackerProvider = Provider<void>((ref) {
  ref.watch(mqttStreamProvider).whenData((messages) async {
    if (messages.isEmpty) {
      return;
    }

    final last = messages.last;
    final payload = (last.payload as MqttPublishMessage).payload.message;
    await ref
        .read(deviceStorageProvider.notifier)
        .updateFromPayload(String.fromCharCodes(payload));
  });
});
