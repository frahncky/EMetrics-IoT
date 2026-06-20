import 'package:e_metrics_iot/src/ui/dashboard/dashboard_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatIndicatorValue', () {
    test('exibe zero quando há uma leitura', () {
      expect(
        formatIndicatorValue(0, fractionDigits: 1, hasMeasurement: true),
        '0.0',
      );
      expect(
        formatIndicatorValue(0, fractionDigits: 3, hasMeasurement: true),
        '0.000',
      );
    });

    test('exibe tracejado somente sem leitura', () {
      expect(
        formatIndicatorValue(0, fractionDigits: 1, hasMeasurement: false),
        '--',
      );
    });
  });
}
