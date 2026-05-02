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
      expect(
        SettingsValidators.validateBroker('https://broker.com'),
        isNotNull,
      );
    });

    test('validateClientId rejeita espaços', () {
      expect(SettingsValidators.validateClientId('meu client'), isNotNull);
    });

    test('validateClientId aceita valor simples', () {
      expect(SettingsValidators.validateClientId('emetrics_app'), isNull);
    });

    test('validatePort exige faixa válida', () {
      expect(SettingsValidators.validatePort(''), isNotNull);
      expect(SettingsValidators.validatePort('abc'), isNotNull);
      expect(SettingsValidators.validatePort('0'), isNotNull);
      expect(SettingsValidators.validatePort('65536'), isNotNull);
      expect(SettingsValidators.validatePort('1883'), isNull);
    });

    test('validateTopic rejeita tópico vazio', () {
      expect(
        SettingsValidators.validateTopic('', fieldLabel: 'o tópico MQTT'),
        isNotNull,
      );
    });

    test('validateTopic rejeita curingas', () {
      expect(
        SettingsValidators.validateTopic(
          'emetrics/#',
          fieldLabel: 'o tópico MQTT',
        ),
        isNotNull,
      );
      expect(
        SettingsValidators.validateTopic(
          'emetrics/+/data',
          fieldLabel: 'o tópico MQTT',
        ),
        isNotNull,
      );
    });

    test('validateTopic aceita tópico específico', () {
      expect(
        SettingsValidators.validateTopic(
          'emetrics/pzem',
          fieldLabel: 'o tópico MQTT',
        ),
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

    test('validateDecimal aceita ponto e vírgula decimal', () {
      expect(
        SettingsValidators.validateDecimal('220.5', fieldLabel: 'a tensão'),
        isNull,
      );
      expect(
        SettingsValidators.validateDecimal('0,85', fieldLabel: 'a tarifa'),
        isNull,
      );
    });

    test('validateDecimal rejeita vazio, texto e zero obrigatório', () {
      expect(
        SettingsValidators.validateDecimal('', fieldLabel: 'a tensão'),
        isNotNull,
      );
      expect(
        SettingsValidators.validateDecimal('abc', fieldLabel: 'a tensão'),
        isNotNull,
      );
      expect(
        SettingsValidators.validateDecimal(
          '0',
          fieldLabel: 'o limite',
          allowZero: false,
        ),
        isNotNull,
      );
    });

    test('validateDecimal respeita faixa', () {
      expect(
        SettingsValidators.validateDecimal(
          '-1',
          fieldLabel: 'a tarifa',
          min: 0,
        ),
        isNotNull,
      );
      expect(
        SettingsValidators.validateDecimal(
          '1001',
          fieldLabel: 'a tarifa',
          max: 1000,
        ),
        isNotNull,
      );
    });
  });
}
