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

class MeasurementSettingsNotifier extends StateNotifier<MeasurementSettings> {
  static const _voltageMinKey = 'measurement_voltage_min';
  static const _voltageMaxKey = 'measurement_voltage_max';
  static const _energyLimitKey = 'measurement_energy_limit_kwh';
  static const _tariffKey = 'measurement_tariff_per_kwh';

  MeasurementSettingsNotifier()
    : super(
        const MeasurementSettings(
          voltageMin: 200,
          voltageMax: 240,
          energyLimitKwh: 10,
          tariffPerKwh: 0,
        ),
      ) {
    load();
  }

  Future<MeasurementSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      voltageMin: prefs.getDouble(_voltageMinKey) ?? state.voltageMin,
      voltageMax: prefs.getDouble(_voltageMaxKey) ?? state.voltageMax,
      energyLimitKwh: prefs.getDouble(_energyLimitKey) ?? state.energyLimitKwh,
      tariffPerKwh: prefs.getDouble(_tariffKey) ?? state.tariffPerKwh,
    );
    return state;
  }

  Future<void> update({
    required double voltageMin,
    required double voltageMax,
    required double energyLimitKwh,
    required double tariffPerKwh,
  }) async {
    state = state.copyWith(
      voltageMin: voltageMin,
      voltageMax: voltageMax,
      energyLimitKwh: energyLimitKwh,
      tariffPerKwh: tariffPerKwh,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_voltageMinKey, state.voltageMin);
    await prefs.setDouble(_voltageMaxKey, state.voltageMax);
    await prefs.setDouble(_energyLimitKey, state.energyLimitKwh);
    await prefs.setDouble(_tariffKey, state.tariffPerKwh);
  }
}

final measurementSettingsProvider =
    StateNotifierProvider<MeasurementSettingsNotifier, MeasurementSettings>(
      (ref) => MeasurementSettingsNotifier(),
    );
