import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'measurement_settings_provider.dart';
import 'metric_provider.dart';
import '../services/alert_service.dart';

final alertProvider = Provider<void>((ref) {
  final settings = ref.watch(measurementSettingsProvider);

  ref.listen(metricsProvider, (prev, next) async {
    final metrics = next.asData?.value;
    if (metrics == null || metrics.isEmpty) return;
    final last = metrics.first;

    // Alerta de tensão fora da faixa
    if (last.voltage < settings.voltageMin ||
        last.voltage > settings.voltageMax) {
      await AlertService.showAlert(
        'Tensão fora da faixa',
        'Valor: ${last.voltage.toStringAsFixed(2)} V',
      );
    }

    // Alerta de consumo excessivo
    if (last.energy > settings.energyLimitKwh) {
      await AlertService.showAlert(
        'Consumo excessivo',
        'Energia acumulada: ${last.energy.toStringAsFixed(2)} kWh',
      );
    }
  });
});
