import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import 'package:fl_chart/fl_chart.dart';

class CompareMetricsPage extends ConsumerStatefulWidget {
  const CompareMetricsPage({super.key});
  @override
  ConsumerState<CompareMetricsPage> createState() => _CompareMetricsPageState();
}

class _CompareMetricsPageState extends ConsumerState<CompareMetricsPage> {
  String _field1 = 'voltage';
  String _field2 = 'current';
  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(metricsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Comparativo de Métricas')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MetricDropdown(
                  value: _field1,
                  onChanged: (v) => setState(() => _field1 = v!),
                ),
                const Icon(Icons.compare_arrows, color: Colors.amber),
                _MetricDropdown(
                  value: _field2,
                  onChanged: (v) => setState(() => _field2 = v!),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: metricsAsync.when(
                data: (metrics) {
                  final data1 = metrics.take(30).toList().reversed.toList();
                  final data2 = metrics.take(30).toList().reversed.toList();
                  List<FlSpot> spots1 = [];
                  List<FlSpot> spots2 = [];
                  for (int i = 0; i < data1.length; i++) {
                    spots1.add(FlSpot(i.toDouble(), _getFieldValue(data1[i], _field1)));
                    spots2.add(FlSpot(i.toDouble(), _getFieldValue(data2[i], _field2)));
                  }
                  return LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots1,
                          isCurved: true,
                          color: Colors.blue,
                          barWidth: 2,
                          dotData: FlDotData(show: false),
                        ),
                        LineChartBarData(
                          spots: spots2,
                          isCurved: true,
                          color: Colors.amber,
                          barWidth: 2,
                          dotData: FlDotData(show: false),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erro ao carregar dados: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getFieldValue(dynamic metric, String field) {
    switch (field) {
      case 'voltage':
        return metric.voltage;
      case 'current':
        return metric.current;
      case 'power':
        return metric.power;
      case 'pf':
        return metric.pf;
      case 'frequency':
        return metric.frequency;
      case 'energy':
        return metric.energy;
      default:
        return 0;
    }
  }
}

class _MetricDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  const _MetricDropdown({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      items: const [
        DropdownMenuItem(value: 'voltage', child: Text('Tensão')),
        DropdownMenuItem(value: 'current', child: Text('Corrente')),
        DropdownMenuItem(value: 'power', child: Text('Potência')),
        DropdownMenuItem(value: 'pf', child: Text('Fator Potência')),
        DropdownMenuItem(value: 'frequency', child: Text('Frequência')),
        DropdownMenuItem(value: 'energy', child: Text('Energia')),
      ],
      onChanged: onChanged,
    );
  }
}
