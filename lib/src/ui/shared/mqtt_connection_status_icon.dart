import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/metric_provider.dart';
import '../../providers/mqtt_status_provider.dart';
import '../../theme/app_colors.dart';

/// Ícones de status para MQTT e comunicação com o dispositivo no AppBar.
///
/// O primeiro ícone representa a conexão MQTT.
/// O segundo ícone representa se há comunicação recente com o dispositivo.
class MqttConnectionStatusIcon extends ConsumerWidget {
  final double rightPadding;

  const MqttConnectionStatusIcon({
    super.key,
    this.rightPadding = 14,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mqttStatusProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final lastMetricTime = metricsAsync.asData?.value.isNotEmpty == true
        ? metricsAsync.asData!.value.first.timestamp
        : null;

    final mqttVisual = _mqttVisual(status);
    final deviceVisual = _deviceVisual(status, lastMetricTime);

    return Padding(
      padding: EdgeInsets.only(right: rightPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: deviceVisual.message,
            child: Icon(
              deviceVisual.icon,
              color: deviceVisual.color,
              size: 24,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: mqttVisual.message,
            child: Icon(
              mqttVisual.icon,
              color: mqttVisual.color,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  _StatusVisual _mqttVisual(MqttStatusState status) {
    switch (status.phase) {
      case MqttConnectionPhase.error:
        return _StatusVisual(
          icon: Icons.error_outline,
          color: AppColors.statusError,
          message: status.lastMessage ?? 'Monitoramento com erro.',
        );
      case MqttConnectionPhase.connecting:
        return const _StatusVisual(
          icon: Icons.sync,
          color: AppColors.statusWarning,
          message: 'MQTT conectando.',
        );
      case MqttConnectionPhase.connected:
        return _StatusVisual(
          icon: status.backgroundActive ? Icons.sensors : Icons.sensors_outlined,
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
    if (status.phase == MqttConnectionPhase.error) {
      return const _StatusVisual(
        icon: Icons.device_unknown,
        color: AppColors.statusError,
        message: 'Comunicação com dispositivo com erro.',
      );
    }

    if (status.phase == MqttConnectionPhase.connecting) {
      return const _StatusVisual(
        icon: Icons.sync,
        color: AppColors.statusWarning,
        message: 'Aguardando comunicação do dispositivo.',
      );
    }

    if (status.phase != MqttConnectionPhase.connected) {
      return const _StatusVisual(
        icon: Icons.sensors_off,
        color: AppColors.statusIdle,
        message: 'Sem comunicação com o dispositivo.',
      );
    }

    if (lastMetricTime == null) {
      return const _StatusVisual(
        icon: Icons.sensors,
        color: AppColors.statusWarning,
        message: 'Dispositivo conectado, sem leituras ainda.',
      );
    }

    final stale = DateTime.now().difference(lastMetricTime).inMinutes >= 5;
    if (stale) {
      return _StatusVisual(
        icon: Icons.sync_problem,
        color: AppColors.statusWarning,
        message: 'Última leitura ${_relativeTime(lastMetricTime)}.',
      );
    }

    return const _StatusVisual(
      icon: Icons.sensors,
      color: AppColors.statusSuccess,
      message: 'Comunicação com dispositivo ativa.',
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
