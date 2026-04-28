import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'metric_provider.dart';
import '../services/alert_service.dart';

final alertProvider = Provider<void>((ref) {
  ref.listen(metricsProvider, (prev, next) async {
    final metrics = next.asData?.value;
    if (metrics == null || metrics.isEmpty) return;
    final last = metrics.first;
    // Alerta de tensão fora da faixa
    if (last.voltage < 200 || last.voltage > 240) {
      await AlertService.showAlert('Tensão fora da faixa', 'Valor: ${last.voltage.toStringAsFixed(2)} V');
    }
    // Alerta de consumo excessivo
    if (last.energy > 10) {
      await AlertService.showAlert('Consumo excessivo', 'Energia acumulada: ${last.energy.toStringAsFixed(2)} kWh');
    }
  });
});
