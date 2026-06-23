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

    test('cria endpoints para prioridade e tempos do Wi-Fi', () {
      expect(
        EspProvisioningService.buildWifiNetworkReorderUri(
          '192.168.4.1',
        ).toString(),
        'http://192.168.4.1/wifi-networks/reorder',
      );
      expect(
        EspProvisioningService.buildWifiConnectionSettingsUri(
          '192.168.4.1',
        ).toString(),
        'http://192.168.4.1/wifi-connection-settings',
      );
      expect(
        EspProvisioningService.buildFirmwareUpdateUri('192.168.4.1').toString(),
        'http://192.168.4.1/firmware/update',
      );
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
        otaPassword: 'chave-ota-segura',
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
      expect(body['initialConnectTimeoutSeconds'], '20');
      expect(body['retryIntervalSeconds'], '15');
      expect(body['fallbackApDelaySeconds'], '60');
      expect(body['otaPassword'], 'chave-ota-segura');
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

    test('buildWifiConnectionSettingsFormData serializa os tempos', () {
      final body = EspProvisioningService.buildWifiConnectionSettingsFormData(
        initialConnectTimeoutSeconds: 30,
        retryIntervalSeconds: 12,
        fallbackApDelaySeconds: 90,
      );

      expect(body, {
        'initialConnectTimeoutSeconds': '30',
        'retryIntervalSeconds': '12',
        'fallbackApDelaySeconds': '90',
      });
    });

    test('parseWifiNetworks decodifica lista do ESP32', () {
      final networks = EspProvisioningService.parseWifiNetworks(
        '{"ok":true,"networks":[{"ssid":"Casa","active":true,"priority":1},{"ssid":"Loja","active":false,"priority":2}]}',
      );

      expect(networks, hasLength(2));
      expect(networks.first.ssid, 'Casa');
      expect(networks.first.active, isTrue);
      expect(networks.first.priority, 1);
      expect(networks.last.ssid, 'Loja');
      expect(networks.last.active, isFalse);
      expect(networks.last.priority, 2);
    });

    test('parseWifiConnectionSettings decodifica os tempos do ESP', () {
      final settings = EspProvisioningService.parseWifiConnectionSettings(
        '{"ok":true,"initialConnectTimeoutSeconds":30,"retryIntervalSeconds":12,"fallbackApDelaySeconds":90}',
      );

      expect(settings.initialConnectTimeoutSeconds, 30);
      expect(settings.retryIntervalSeconds, 12);
      expect(settings.fallbackApDelaySeconds, 90);
    });
  });
}
