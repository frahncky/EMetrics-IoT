import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../data/metric_model.dart';
import '../data/metric_repository.dart';
import '../providers/alert_history_provider.dart';
import '../providers/integration_settings_provider.dart';
import '../providers/measurement_settings_provider.dart';
import 'alert_service.dart';
import 'integration_service.dart';

class BackgroundMetricProcessor {
  static const _alertHistoryKey = 'alert_history_records';
  static const _voltageGateKey = 'background_alert_voltage_out_of_range';
  static const _energyGateKey = 'background_alert_energy_exceeded';

  Future<void> process(
    Metric metric, {
    required MetricRepository repository,
  }) async {
    await _processAlerts(metric);
    await _submitIntegration(metric, repository);
  }

  Future<void> _processAlerts(Metric metric) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = await loadMeasurementSettings();
      await _evaluateAlert(
        prefs: prefs,
        gateKey: _voltageGateKey,
        isActive:
            metric.voltage < settings.voltageMin ||
            metric.voltage > settings.voltageMax,
        record: AlertRecord(
          id: 'voltage_${metric.timestamp.millisecondsSinceEpoch}',
          title: 'Tensão fora da faixa',
          message: 'Valor: ${metric.voltage.toStringAsFixed(2)} V',
          type: 'voltage',
          severity: AlertSeverity.warning,
          createdAt: DateTime.now(),
        ),
      );
      await _evaluateAlert(
        prefs: prefs,
        gateKey: _energyGateKey,
        isActive: metric.energy > settings.energyLimitKwh,
        clearWhenInactive: metric.energy <= settings.energyLimitKwh * 0.95,
        record: AlertRecord(
          id: 'energy_${metric.timestamp.millisecondsSinceEpoch}',
          title: 'Consumo excessivo',
          message: 'Energia acumulada: ${metric.energy.toStringAsFixed(2)} kWh',
          type: 'energy',
          severity: AlertSeverity.critical,
          createdAt: DateTime.now(),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Falha ao processar alertas em segundo plano',
        name: 'BackgroundMetricProcessor',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _evaluateAlert({
    required SharedPreferences prefs,
    required String gateKey,
    required bool isActive,
    required AlertRecord record,
    bool clearWhenInactive = true,
  }) async {
    final wasActive = prefs.getBool(gateKey) ?? false;
    if (!isActive) {
      if (clearWhenInactive && wasActive) {
        await prefs.setBool(gateKey, false);
      }
      return;
    }
    if (wasActive) {
      return;
    }

    await _persistAlertRecord(prefs, record);
    await prefs.setBool(gateKey, true);
    await AlertService.showAlert(record.title, record.message);
  }

  Future<void> _persistAlertRecord(
    SharedPreferences prefs,
    AlertRecord record,
  ) async {
    final raw = prefs.getString(_alertHistoryKey);
    final records = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            records.add(Map<String, dynamic>.from(item));
          }
        }
      }
    }
    records.removeWhere((item) => item['id'] == record.id);
    records.insert(0, record.toMap());
    await prefs.setString(
      _alertHistoryKey,
      jsonEncode(records.take(100).toList()),
    );
  }

  Future<void> _submitIntegration(
    Metric metric,
    MetricRepository repository,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = IntegrationService(
        repository: repository,
        loadSettings: loadIntegrationSettings,
      );
      await service.submitMetric(
        metric,
        profileId: prefs.getString('mqtt_active_profile_id'),
      );
      await service.flushPendingQueue();
    } catch (error, stackTrace) {
      developer.log(
        'Falha ao enviar métrica em segundo plano',
        name: 'BackgroundMetricProcessor',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
