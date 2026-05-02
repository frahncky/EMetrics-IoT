import 'package:e_metrics_iot/src/services/esp_provisioning_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspProvisioningService', () {
    test('buildProvisioningUri cria endpoint padrao com host cru', () {
      final uri = EspProvisioningService.buildProvisioningUri('192.168.4.1');

      expect(uri.toString(), 'http://192.168.4.1/provision');
    });

    test('buildProvisioningUri preserva schema e porta existentes', () {
      final uri = EspProvisioningService.buildProvisioningUri(
        'http://10.0.0.55:8080',
      );

      expect(uri.toString(), 'http://10.0.0.55:8080/provision');
    });

    test('buildFormData serializa payload esperado', () {
      final body = EspProvisioningService.buildFormData(
        wifiSsid: ' MinhaRede ',
        wifiPassword: 'wifi123',
        mqttHost: ' broker.local ',
        mqttPort: 1883,
        mqttUser: ' user ',
        mqttPassword: 'pass',
        mqttTopic: ' emetrics/pzem ',
        mqttRequestTopic: ' emetrics/pzem/history/request ',
        mqttClientId: ' esp32-01 ',
        useTls: true,
      );

      expect(body['ssid'], 'MinhaRede');
      expect(body['wifiPassword'], 'wifi123');
      expect(body['mqttHost'], 'broker.local');
      expect(body['mqttPort'], '1883');
      expect(body['mqttUser'], 'user');
      expect(body['mqttPassword'], 'pass');
      expect(body['mqttTopic'], 'emetrics/pzem');
      expect(body['mqttRequestTopic'], 'emetrics/pzem/history/request');
      expect(body['clientId'], 'esp32-01');
      expect(body['useTls'], '1');
    });
  });
}
