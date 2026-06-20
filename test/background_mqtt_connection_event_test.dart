import 'package:e_metrics_iot/src/services/background_mqtt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interpreta eventos de conexão do serviço MQTT em segundo plano', () {
    final connected = BackgroundMqttConnectionEvent.fromPayload({
      'phase': 'connected',
    });
    final failed = BackgroundMqttConnectionEvent.fromPayload({
      'phase': 'error',
      'message': 'Broker indisponível.',
    });

    expect(connected.phase, BackgroundMqttConnectionPhase.connected);
    expect(failed.phase, BackgroundMqttConnectionPhase.error);
    expect(failed.message, 'Broker indisponível.');
  });
}
