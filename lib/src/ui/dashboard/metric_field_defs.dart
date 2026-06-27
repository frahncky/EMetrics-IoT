import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class MetricFieldDef {
  final String key;
  final String label;
  final String? unit;
  final IconData icon;
  final Color color;
  final int fractionDigits;
  final bool extraCompact;

  const MetricFieldDef({
    required this.key,
    required this.label,
    this.unit,
    required this.icon,
    required this.color,
    this.fractionDigits = 1,
    this.extraCompact = false,
  });
}

const kAllMetricFields = <MetricFieldDef>[
  MetricFieldDef(
    key: 'voltage',
    label: 'Tensão',
    unit: 'V',
    icon: Icons.electrical_services,
    color: AppColors.metricVoltage,
    fractionDigits: 1,
  ),
  MetricFieldDef(
    key: 'current',
    label: 'Corrente',
    unit: 'A',
    icon: Icons.bolt_outlined,
    color: AppColors.metricCurrent,
    fractionDigits: 3,
  ),
  MetricFieldDef(
    key: 'power',
    label: 'P. Ativa',
    unit: 'W',
    icon: Icons.flash_on_outlined,
    color: AppColors.metricActive,
    fractionDigits: 1,
  ),
  MetricFieldDef(
    key: 'apparent',
    label: 'P. Aparente',
    unit: 'VA',
    icon: Icons.data_usage,
    color: AppColors.metricApparent,
    fractionDigits: 1,
  ),
  MetricFieldDef(
    key: 'reactive',
    label: 'P. Reativa',
    unit: 'VAr',
    icon: Icons.waves,
    color: AppColors.metricReactive,
    fractionDigits: 1,
  ),
  MetricFieldDef(
    key: 'pf',
    label: 'FP',
    icon: Icons.speed_outlined,
    color: AppColors.metricPf,
    fractionDigits: 2,
    extraCompact: true,
  ),
  MetricFieldDef(
    key: 'frequency',
    label: 'Frequência',
    unit: 'Hz',
    icon: Icons.ssid_chart,
    color: AppColors.metricFrequency,
    fractionDigits: 2,
    extraCompact: true,
  ),
  MetricFieldDef(
    key: 'energy',
    label: 'E. Ativa',
    unit: 'kWh',
    icon: Icons.battery_charging_full_outlined,
    color: AppColors.metricEnergy,
    fractionDigits: 3,
  ),
  MetricFieldDef(
    key: 'energy_apparent',
    label: 'E. Aparente',
    unit: 'kVAh',
    icon: Icons.data_usage,
    color: AppColors.metricApparent,
    fractionDigits: 3,
  ),
  MetricFieldDef(
    key: 'energy_reactive',
    label: 'E. Reativa',
    unit: 'kVArh',
    icon: Icons.waves,
    color: AppColors.metricReactive,
    fractionDigits: 3,
  ),
  MetricFieldDef(
    key: 'temperature',
    label: 'Temperatura',
    unit: '°C',
    icon: Icons.device_thermostat,
    color: AppColors.statusWarning,
    fractionDigits: 1,
    extraCompact: true,
  ),
];

MetricFieldDef fieldByKey(String key) => kAllMetricFields.firstWhere(
  (f) => f.key == key,
  orElse: () => kAllMetricFields.first,
);
