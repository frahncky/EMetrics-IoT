import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/alert_history_provider.dart';

class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas'),
        actions: [
          if (alerts.isNotEmpty)
            IconButton(
              tooltip: 'Limpar alertas',
              onPressed: () => ref.read(alertHistoryProvider.notifier).clear(),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: alerts.isEmpty
          ? Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.notifications_none, size: 44),
                      SizedBox(height: 12),
                      Text(
                        'Nenhum alerta registrado até agora.',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Quando tensão ou consumo saírem do esperado, os eventos aparecerão aqui.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final alert = alerts[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: _severityColor(alert.severity).withValues(alpha: 0.18),
                      child: Icon(
                        _severityIcon(alert.severity),
                        color: _severityColor(alert.severity),
                      ),
                    ),
                    title: Text(alert.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        Text(alert.message),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text(_severityLabel(alert.severity))),
                            Chip(label: Text(_formatTimestamp(alert.createdAt))),
                            if (alert.acknowledged)
                              const Chip(label: Text('Reconhecido')),
                          ],
                        ),
                      ],
                    ),
                    trailing: alert.acknowledged
                        ? null
                        : TextButton(
                            onPressed: () => ref
                                .read(alertHistoryProvider.notifier)
                                .acknowledge(alert.id),
                            child: const Text('Reconhecer'),
                          ),
                  ),
                );
              },
            ),
    );
  }

  static String _formatTimestamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  static String _severityLabel(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.warning:
        return 'Atenção';
      case AlertSeverity.critical:
        return 'Crítico';
      case AlertSeverity.info:
        return 'Informativo';
    }
  }

  static IconData _severityIcon(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.warning:
        return Icons.warning_amber_rounded;
      case AlertSeverity.critical:
        return Icons.error_outline;
      case AlertSeverity.info:
        return Icons.info_outline;
    }
  }

  static Color _severityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.warning:
        return const Color(0xFFD97706);
      case AlertSeverity.critical:
        return const Color(0xFFDC2626);
      case AlertSeverity.info:
        return const Color(0xFF2563EB);
    }
  }
}
