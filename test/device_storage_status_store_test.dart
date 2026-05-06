import 'package:e_metrics_iot/src/services/device_storage_status_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDeviceStorageStatusFromMqtt', () {
    test('extrai percentual de uso do SD a partir de storage aninhado', () {
      final status = parseDeviceStorageStatusFromMqtt(
        '{"voltage":220,"current":1,"power":100,"pf":0.98,"frequency":60,"energy":1,'
        '"storage":{"usingSd":true,"sdAvailable":true,"sdUsedBytes":512,"sdTotalBytes":1024}}',
      );

      expect(status, isNotNull);
      expect(status!.sdAvailable, isTrue);
      expect(status.usingSd, isTrue);
      expect(status.sdUsagePercent, 50);
      expect(status.sdUsedBytes, 512);
      expect(status.sdTotalBytes, 1024);
    });

    test('aceita campo percentual plano', () {
      final status = parseDeviceStorageStatusFromMqtt(
        '{"sdUsagePercent":72.4,"sdAvailable":true}',
      );

      expect(status, isNotNull);
      expect(status!.sdUsagePercent, 72.4);
      expect(status.sdAvailable, isTrue);
    });
  });
}
