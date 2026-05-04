import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/mqtt_status_provider.dart';
import '../../theme/app_colors.dart';

/// Ícone de status de conexão MQTT para uso em AppBar.
///
/// Exibe cor/ícone conforme o estado atual da conexão e mostra detalhes no tooltip.
class MqttConnectionStatusIcon extends ConsumerWidget {
  const MqttConnectionStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mqttStatusProvider);
    final visual = _statusVisual(status);

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Tooltip(
        message: visual.message,
        child: Icon(
          visual.icon,
          color: visual.color,
          size: 24,
        ),
      ),
    );
  }

  _StatusVisual _statusVisual(MqttStatusState status) {
    switch (status.phase) {
      case MqttConnectionPhase.error:
        return _StatusVisual(
          icon: Icons.error_outline,
          color: AppColors.statusError,
          message: status.lastMessage ?? 'Monitoramento com erro.',
        );
      case MqttConnectionPhase.connecting:
        return _StatusVisual(
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
