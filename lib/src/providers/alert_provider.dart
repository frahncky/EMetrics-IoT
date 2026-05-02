import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alert_service.dart';
import 'alert_history_provider.dart';
import 'measurement_settings_provider.dart';
import 'metric_provider.dart';

class _AlertGateState {
  final bool voltageOutOfRange;
  final bool energyExceeded;

  const _AlertGateState({
    required this.voltageOutOfRange,
    required this.energyExceeded,
  });

  const _AlertGateState.initial()
    : voltageOutOfRange = false,
      energyExceeded = false;

  _AlertGateState copyWith({bool? voltageOutOfRange, bool? energyExceeded}) {
    return _AlertGateState(
      voltageOutOfRange: voltageOutOfRange ?? this.voltageOutOfRange,
      energyExceeded: energyExceeded ?? this.energyExceeded,
    );
  }
}

class _AlertGateNotifier extends StateNotifier<_AlertGateState> {
  _AlertGateNotifier() : super(const _AlertGateState.initial());

  void setVoltageOutOfRange(bool value) {
    state = state.copyWith(voltageOutOfRange: value);
  }

  void setEnergyExceeded(bool value) {
    state = state.copyWith(energyExceeded: value);
  }
}

final _alertGateProvider = StateNotifierProvider<_AlertGateNotifier, _AlertGateState>(
  (ref) => _AlertGateNotifier(),
);

final alertProvider = Provider<void>((ref) {
  final settings = ref.watch(measurementSettingsProvider);

  ref.listen(metricsProvider, (prev, next) async {
    final metrics = next.asData?.value;
    if (metrics == null || metrics.isEmpty) return;
    final last = metrics.first;
    final gate = ref.read(_alertGateProvider);
    final history = ref.read(alertHistoryProvider.notifier);

    Future<void> registerAlert({
      required String type,
      required String title,
      required String message,
      required AlertSeverity severity,
    }) async {
      final alert = AlertRecord(
        id: '${type}_${last.timestamp.millisecondsSinceEpoch}',
        title: title,
        message: message,
        type: type,
        severity: severity,
        createdAt: DateTime.now(),
      );
      await history.add(alert);
      await AlertService.showAlert(title, message);
    }

    final voltageOutOfRange =
        last.voltage < settings.voltageMin || last.voltage > settings.voltageMax;
    if (voltageOutOfRange && !gate.voltageOutOfRange) {
      await registerAlert(
        type: 'voltage',
        title: 'Tensão fora da faixa',
        message: 'Valor: ${last.voltage.toStringAsFixed(2)} V',
        severity: AlertSeverity.warning,
      );
      ref.read(_alertGateProvider.notifier).setVoltageOutOfRange(true);
    } else if (!voltageOutOfRange && gate.voltageOutOfRange) {
      ref.read(_alertGateProvider.notifier).setVoltageOutOfRange(false);
    }

    final energyExceeded = last.energy > settings.energyLimitKwh;
    if (energyExceeded && !gate.energyExceeded) {
      await registerAlert(
        type: 'energy',
        title: 'Consumo excessivo',
        message: 'Energia acumulada: ${last.energy.toStringAsFixed(2)} kWh',
        severity: AlertSeverity.critical,
      );
      ref.read(_alertGateProvider.notifier).setEnergyExceeded(true);
    } else if (
        last.energy <= settings.energyLimitKwh * 0.95 && gate.energyExceeded) {
      ref.read(_alertGateProvider.notifier).setEnergyExceeded(false);
    }
  });
});
