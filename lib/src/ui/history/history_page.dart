import 'history_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import 'history_filter.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  HistoryPeriod _period = HistoryPeriod.dia;

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(metricsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Consumo')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          HistoryFilter(
            selected: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: metricsAsync.when(
              data: (metrics) {
                final filtered = _filterMetrics(metrics, _period);
                if (filtered.isEmpty) {
                  return const Center(child: Text('Nenhum dado para o período.'));
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: HistoryExportButton(metrics: filtered.cast()),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final m = filtered[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: const Icon(Icons.history, color: Colors.amber, size: 32),
                              title: Text(
                                '${m.voltage.toStringAsFixed(2)} V, ${m.current.toStringAsFixed(2)} A, ${m.power.toStringAsFixed(2)} W',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text('${m.timestamp}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.bolt, color: Colors.blueGrey, size: 18),
                                  Text('${m.energy.toStringAsFixed(2)} kWh', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Registro de ${m.timestamp} selecionado.')),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro ao carregar histórico: $e')),
            ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _filterMetrics(List<dynamic> metrics, HistoryPeriod period) {
    final now = DateTime.now();
    DateTime from;
    switch (period) {
      case HistoryPeriod.hora:
        from = now.subtract(const Duration(hours: 1));
        break;
      case HistoryPeriod.dia:
        from = DateTime(now.year, now.month, now.day);
        break;
      case HistoryPeriod.semana:
        from = now.subtract(const Duration(days: 7));
        break;
      case HistoryPeriod.mes:
        from = DateTime(now.year, now.month, 1);
        break;
    }
    return metrics.where((m) => m.timestamp.isAfter(from)).toList();
  }
}
