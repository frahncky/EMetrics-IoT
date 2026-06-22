import 'package:e_metrics_iot/src/providers/mqtt_metric_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMetricFromMqtt', () {
    test('usa o timestamp de medição do ESP quando disponível', () {
      final metric = parseMetricFromMqtt(
        '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,'
        '"frequency":60,"energy":1.23,"temperature":42.1,'
        '"crcErrors":0,"timestamp":1746316850000,"sequence":7,'
        '"timeSynced":true}',
      );

      expect(metric, isNotNull);
      expect(metric!.timestamp.millisecondsSinceEpoch, 1746316850000);
      expect(metric.receivedAt, isNotNull);
      expect(metric.temperature, 42.1);
      expect(metric.crcErrors, 0);
    });

    test(
      'usa a hora de recepção quando o ESP ainda não sincronizou o relógio',
      () {
        final before = DateTime.now();
        final metric = parseMetricFromMqtt(
          '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,'
          '"frequency":60,"energy":1.23,"timestamp":0,"timeSynced":false}',
        );
        final after = DateTime.now();

        expect(metric, isNotNull);
        expect(
          metric!.timestamp.millisecondsSinceEpoch,
          inInclusiveRange(
            before.millisecondsSinceEpoch,
            after.millisecondsSinceEpoch,
          ),
        );
      },
    );

    test('rejeita objeto que não seja telemetria válida', () {
      expect(parseMetricFromMqtt('[1,2,3]'), isNull);
      expect(parseMetricFromMqtt('{"voltage":220.1}'), isNull);
    });
  });
}
