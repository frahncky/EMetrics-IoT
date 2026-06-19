import 'package:e_metrics_iot/src/services/esp_provisioning_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspProvisioningService', () {
    test('buildProvisioningUri cria endpoint padrão com host cru', () {
      final uri = EspProvisioningService.buildProvisioningUri('192.168.4.1');

      expect(uri.toString(), 'http://192.168.4.1/provision');
    });

    test('buildWifiNetworksUri cria endpoint de redes salvas', () {
      final uri = EspProvisioningService.buildWifiNetworksUri('192.168.4.1');

      expect(uri.toString(), 'http://192.168.4.1/wifi-networks');
    });

    test('buildProvisioningUri preserva schema e porta existentes', () {
      final uri = EspProvisioningService.buildProvisioningUri(
        'http://10.0.0.55:8080',
      );

      expect(uri.toString(), 'http://10.0.0.55:8080/provision');
    });

    test('buildDefaultEspClientId cria Client ID diferente do app', () {
      final clientId = EspProvisioningService.buildDefaultEspClientId(
        'emetrics_app',
      );

      expect(clientId, 'emetrics_app_esp32');
      expect(clientId, isNot('emetrics_app'));
    });

    test('buildDefaultEspClientId respeita limite do formulário', () {
      final clientId = EspProvisioningService.buildDefaultEspClientId(
        'app_${'x' * 80}',
      );

      expect(clientId.length, lessThanOrEqualTo(50));
      expect(clientId.endsWith('_esp32'), isTrue);
    });

    test('buildDefaultEspClientId usa padrão quando app não tem Client ID', () {
      final clientId = EspProvisioningService.buildDefaultEspClientId('  ');

      expect(clientId, 'esp32_pzem_001');
    });

    test('buildFormData serializa payload esperado', () {
      final body = EspProvisioningService.buildFormData(
        wifiSsid: ' MinhaRede ',
        wifiUsername: ' usuario.rede ',
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
  expect(body['wifiUsername'], 'usuario.rede');
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

    test('buildWifiNetworkFormData serializa edição de rede', () {
      final body = EspProvisioningService.buildWifiNetworkFormData(
        ssid: ' NovaRede ',
        wifiUsername: ' user.enterprise ',
        wifiPassword: '',
        oldSsid: ' Antiga ',
        keepUsername: true,
        keepPassword: true,
      );

      expect(body['ssid'], 'NovaRede');
      expect(body['oldSsid'], 'Antiga');
      expect(body['wifiUsername'], 'user.enterprise');
      expect(body['wifiPassword'], '');
      expect(body['keepUsername'], '1');
      expect(body['keepPassword'], '1');
    });

    test('parseWifiNetworks decodifica lista do ESP32', () {
      final networks = EspProvisioningService.parseWifiNetworks(
        '{"ok":true,"networks":[{"ssid":"Casa","active":true},{"ssid":"Loja","active":false}]}',
      );

      expect(networks, hasLength(2));
      expect(networks.first.ssid, 'Casa');
      expect(networks.first.active, isTrue);
      expect(networks.last.ssid, 'Loja');
      expect(networks.last.active, isFalse);
    });
  });
}
