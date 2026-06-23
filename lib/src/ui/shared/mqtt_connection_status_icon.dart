import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/metric_model.dart';
import '../../providers/metric_provider.dart';
import '../../providers/mqtt_provider.dart';
import '../../providers/mqtt_status_provider.dart';
import '../../services/background_mqtt_service.dart';
import '../../services/mqtt_service.dart';
import '../../theme/app_colors.dart';

/// Ícones de status para MQTT e comunicação com o dispositivo no AppBar.
///
/// O primeiro ícone representa a conexão MQTT.
/// O segundo ícone representa se há comunicação recente com o dispositivo.
class MqttConnectionStatusIcon extends ConsumerWidget {
  static const _warningAfter = Duration(seconds: 15);

  final double rightPadding;

  const MqttConnectionStatusIcon({super.key, this.rightPadding = 14});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mqttStatusProvider);
    final metricsData = ref.watch(metricsProvider).asData;
    final lastMetricTime = _lastMetricReceivedAt(metricsData?.value);

    final mqttVisual = _mqttVisual(status);
    final deviceVisual = _deviceVisual(status, lastMetricTime);

    return Padding(
      padding: EdgeInsets.only(right: rightPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            message: deviceVisual.message,
            child: Icon(deviceVisual.icon, color: deviceVisual.color, size: 24),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const Key('mqtt-status-quick-actions'),
            onLongPress: () => _showQuickConnectionDialog(context, ref),
            child: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              message: mqttVisual.message,
              child: Icon(mqttVisual.icon, color: mqttVisual.color, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickConnectionDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Conexão MQTT'),
          content: Text(
            'Segure o ícone MQTT para abrir este atalho rápido.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _disconnectFromQuickActions(context, ref);
              },
              icon: const Icon(Icons.cloud_off_outlined),
              label: const Text('Desconectar'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _connectFromQuickActions(context, ref);
              },
              icon: const Icon(Icons.cloud_done_outlined),
              label: const Text('Conectar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectFromQuickActions(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final statusNotifier = ref.read(mqttStatusProvider.notifier);
    try {
      statusNotifier.markConnecting();
      await BackgroundMqttService.stop();
      ref.invalidate(mqttServiceProvider);
      final mqttService = ref.read(mqttServiceProvider);
      await mqttService.connect();
      mqttService.subscribe();
      statusNotifier.setBackgroundActive(false);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conectado ao broker MQTT no app.')),
      );
    } catch (error) {
      statusNotifier.markError(_toUserMessage(error));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao conectar: ${_toUserMessage(error)}')),
      );
    }
  }

  Future<void> _disconnectFromQuickActions(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final statusNotifier = ref.read(mqttStatusProvider.notifier);
    final mqttService = ref.read(mqttServiceProvider);
    await BackgroundMqttService.stop();
    mqttService.disconnect();
    ref.invalidate(mqttServiceProvider);
    statusNotifier.setBackgroundActive(false);
    statusNotifier.markDisconnected('Monitoramento MQTT pausado.');
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Monitoramento MQTT pausado.')),
    );
  }

  String _toUserMessage(Object error) {
    if (error is MqttServiceException) {
      return error.message;
    }

    const prefix = 'Exception: ';
    final text = error.toString();
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }

  _StatusVisual _mqttVisual(MqttStatusState status) {
    switch (status.phase) {
      case MqttConnectionPhase.error:
        return _StatusVisual(
          icon: Icons.cloud_off,
          color: AppColors.statusError,
          message: status.lastMessage ?? 'Monitoramento com erro.',
        );
      case MqttConnectionPhase.connecting:
        return const _StatusVisual(
          icon: Icons.cloud_sync,
          color: AppColors.statusWarning,
          message: 'MQTT conectando.',
        );
      case MqttConnectionPhase.connected:
        return _StatusVisual(
          icon: status.backgroundActive ? Icons.cloud_sync : Icons.cloud_done,
          color: AppColors.statusSuccess,
          message: status.backgroundActive
              ? 'Monitoramento ativo em segundo plano.'
              : 'MQTT conectado.',
        );
      case MqttConnectionPhase.disconnected:
        return _StatusVisual(
          icon: Icons.cloud_off,
          color: AppColors.statusIdle,
          message: status.lastMessage ?? 'MQTT desconectado.',
        );
    }
  }

  _StatusVisual _deviceVisual(
    MqttStatusState status,
    DateTime? lastMetricTime,
  ) {
    if (status.phase != MqttConnectionPhase.connected) {
      return const _StatusVisual(
        icon: Icons.electric_meter_outlined,
        color: AppColors.statusIdle,
        message: 'MQTT desconectado. Medidor sem telemetria.',
      );
    }

    if (lastMetricTime == null) {
      return const _StatusVisual(
        icon: Icons.electric_meter,
        color: AppColors.statusWarning,
        message: 'MQTT conectado, mas o medidor não está enviando dados.',
      );
    }

    final elapsed = DateTime.now().difference(lastMetricTime);
    if (elapsed >= _warningAfter) {
      return _StatusVisual(
        icon: Icons.electric_meter,
        color: AppColors.statusWarning,
        message:
            'MQTT conectado, mas sem dados do medidor. Última leitura ${_relativeTime(lastMetricTime)}.',
      );
    }

    return const _StatusVisual(
      icon: Icons.electric_meter,
      color: AppColors.statusSuccess,
      message: 'Medidor conectado e enviando dados.',
    );
  }

  DateTime? _lastMetricReceivedAt(List<Metric>? metrics) {
    if (metrics == null || metrics.isEmpty) {
      return null;
    }

    return metrics
        .map((metric) => metric.receivedAt ?? metric.timestamp)
        .reduce(
          (latest, current) => current.isAfter(latest) ? current : latest,
        );
  }

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) {
      return 'há instantes';
    }
    if (difference.inHours < 1) {
      return 'há ${difference.inMinutes} min';
    }
    return 'há ${difference.inHours} h';
  }
}

class _StatusVisual {
  final IconData icon;
  final Color color;
  final String message;

  const _StatusVisual({
    required this.icon,
    required this.color,
    required this.message,
  });
}
