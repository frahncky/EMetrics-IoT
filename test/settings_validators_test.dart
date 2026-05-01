import 'package:e_metrics_iot/src/ui/settings/settings_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsValidators', () {
    test('validateBroker retorna erro para vazio', () {
      expect(SettingsValidators.validateBroker(''), isNotNull);
    });

    test('validateBroker aceita host válido', () {
      expect(SettingsValidators.validateBroker('test.mosquitto.org'), isNull);
    });

    test('validateBroker rejeita URL com protocolo', () {
      expect(SettingsValidators.validateBroker('https://broker.com'), isNotNull);
    });

    test('validateClientId rejeita espaços', () {
      expect(SettingsValidators.validateClientId('meu client'), isNotNull);
    });

    test('validateClientId aceita valor simples', () {
      expect(SettingsValidators.validateClientId('emetrics_app'), isNull);
    });

    test('validateTopic rejeita tópico vazio', () {
      expect(
        SettingsValidators.validateTopic('', fieldLabel: 'o tópico MQTT'),
        isNotNull,
      );
    });

    test('validateTopic rejeita curingas', () {
      expect(
        SettingsValidators.validateTopic('emetrics/#', fieldLabel: 'o tópico MQTT'),
        isNotNull,
      );
      expect(
        SettingsValidators.validateTopic('emetrics/+/data', fieldLabel: 'o tópico MQTT'),
        isNotNull,
      );
    });

    test('validateTopic aceita tópico específico', () {
      expect(
        SettingsValidators.validateTopic('emetrics/pzem', fieldLabel: 'o tópico MQTT'),
        isNull,
      );
    });

    test('validateInterval exige número positivo', () {
      expect(SettingsValidators.validateInterval('0'), isNotNull);
      expect(SettingsValidators.validateInterval('-1'), isNotNull);
      expect(SettingsValidators.validateInterval('abc'), isNotNull);
    });

    test('validateInterval aceita faixa válida', () {
      expect(SettingsValidators.validateInterval('5'), isNull);
      expect(SettingsValidators.validateInterval('3600'), isNull);
    });
  });
}