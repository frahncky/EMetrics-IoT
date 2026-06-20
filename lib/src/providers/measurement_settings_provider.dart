import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MeasurementSettings {
  final double voltageMin;
  final double voltageMax;
  final double energyLimitKwh;
  final double tariffPerKwh;

  const MeasurementSettings({
    required this.voltageMin,
    required this.voltageMax,
    required this.energyLimitKwh,
    required this.tariffPerKwh,
  });

  MeasurementSettings copyWith({
    double? voltageMin,
    double? voltageMax,
    double? energyLimitKwh,
    double? tariffPerKwh,
  }) {
    return MeasurementSettings(
      voltageMin: voltageMin ?? this.voltageMin,
      voltageMax: voltageMax ?? this.voltageMax,
      energyLimitKwh: energyLimitKwh ?? this.energyLimitKwh,
      tariffPerKwh: tariffPerKwh ?? this.tariffPerKwh,
    );
  }
}

const defaultMeasurementSettings = MeasurementSettings(
  voltageMin: 200,
  voltageMax: 240,
  energyLimitKwh: 10,
  tariffPerKwh: 0,
);

Future<MeasurementSettings> loadMeasurementSettings() async {
  const defaults = defaultMeasurementSettings;
  final prefs = await SharedPreferences.getInstance();
  return MeasurementSettings(
    voltageMin:
        prefs.getDouble(MeasurementSettingsNotifier.voltageMinKey) ??
        defaults.voltageMin,
    voltageMax:
        prefs.getDouble(MeasurementSettingsNotifier.voltageMaxKey) ??
        defaults.voltageMax,
    energyLimitKwh:
        prefs.getDouble(MeasurementSettingsNotifier.energyLimitKey) ??
        defaults.energyLimitKwh,
    tariffPerKwh:
        prefs.getDouble(MeasurementSettingsNotifier.tariffKey) ??
        defaults.tariffPerKwh,
  );
}

class MeasurementSettingsNotifier extends StateNotifier<MeasurementSettings> {
  static const voltageMinKey = 'measurement_voltage_min';
  static const voltageMaxKey = 'measurement_voltage_max';
  static const energyLimitKey = 'measurement_energy_limit_kwh';
  static const tariffKey = 'measurement_tariff_per_kwh';
  var _revision = 0;

  MeasurementSettingsNotifier() : super(defaultMeasurementSettings) {
    load();
  }

  Future<MeasurementSettings> load() async {
    final loadRevision = _revision;
    final nextState = await loadMeasurementSettings();
    if (mounted && loadRevision == _revision) {
      state = nextState;
    }
    return state;
  }

  Future<void> update({
    required double voltageMin,
    required double voltageMax,
    required double energyLimitKwh,
    required double tariffPerKwh,
  }) async {
    _revision++;
    state = state.copyWith(
      voltageMin: voltageMin,
      voltageMax: voltageMax,
      energyLimitKwh: energyLimitKwh,
      tariffPerKwh: tariffPerKwh,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(voltageMinKey, state.voltageMin);
    await prefs.setDouble(voltageMaxKey, state.voltageMax);
    await prefs.setDouble(energyLimitKey, state.energyLimitKwh);
    await prefs.setDouble(tariffKey, state.tariffPerKwh);
  }
}

final measurementSettingsProvider =
    StateNotifierProvider<MeasurementSettingsNotifier, MeasurementSettings>(
      (ref) => MeasurementSettingsNotifier(),
    );
