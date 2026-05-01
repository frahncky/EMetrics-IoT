import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import 'history_filter.dart';
import 'history_chart.dart';
// Função utilitária igual ao dashboard
String formatWithSIPrefix(num value, {int? fractionDigits}) {
  if (value == 0 || value.isNaN) return '--';
  final abs = value.abs();
  int digits(double v) {
    if (v >= 100) return 0;
    if (v >= 10) return 1;

    return 2;
  }
  if (abs >= 1e9) {
    final d = fractionDigits ?? digits(value / 1e9);
    return (value / 1e9).toStringAsFixed(d) + ' G';
  } else if (abs >= 1e6) {
    final d = fractionDigits ?? digits(value / 1e6);
    return (value / 1e6).toStringAsFixed(d) + ' M';
  } else if (abs >= 1e3) {
    final d = fractionDigits ?? digits(value / 1e3);
    return (value / 1e3).toStringAsFixed(d) + ' K';
  } else if (abs < 1e-3 && abs > 0) {
    final d = fractionDigits ?? digits(value * 1e6);
    return (value * 1e6).toStringAsFixed(d) + ' μ';
  } else if (abs < 1 && abs >= 1e-3) {
    final d = fractionDigits ?? digits(value * 1e3);
    return (value * 1e3).toStringAsFixed(d) + ' m';
  } else {
    final d = fractionDigits ?? digits(value.toDouble());
    return value.toStringAsFixed(d);
  }
}


// Seletor igual ao Dashboard, mas para histórico
class _HistoryChartSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _HistoryChartSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const fields = [
      {'label': 'Potência', 'value': 'power'},
      {'label': 'Corrente', 'value': 'current'},
      {'label': 'Tensão', 'value': 'voltage'},
      {'label': 'Energia', 'value': 'energy'},
      {'label': 'Fator Potência', 'value': 'pf'},
      {'label': 'Frequência', 'value': 'frequency'},
    ];
    return Wrap(
      spacing: 8,
      children: fields.map((f) => ChoiceChip(
        label: Text(f['label']!),
        selected: selected == f['value'],
        onSelected: (_) => onChanged(f['value']!),
      )).toList(),
    );
  }
}

// Botão para selecionar campo do gráfico

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
    String _selectedField1 = 'power';
    String _selectedField2 = 'energy';
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
          // Seletor de campo agora está dentro do gráfico
          Expanded(
            child: metricsAsync.when(
              data: (metrics) {
                final filtered = _filterMetrics(metrics, _period);
                // Apenas gráficos
                return Column(
                  children: [
                    // Espaço fixo para o gráfico 1
                    SizedBox(
                      height: 180,
                      child: HistoryChart(
                        metrics: filtered.cast(),
                        field: _selectedField1,
                        fieldSelector: (context) => _HistoryChartSelector(
                          selected: _selectedField1,
                          onChanged: (f) => setState(() => _selectedField1 = f),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Espaço fixo para o gráfico 2
                    SizedBox(
                      height: 180,
                      child: HistoryChart(
                        metrics: filtered.cast(),
                        field: _selectedField2,
                        fieldSelector: (context) => _HistoryChartSelector(
                          selected: _selectedField2,
                          onChanged: (f) => setState(() => _selectedField2 = f),
                        ),
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
