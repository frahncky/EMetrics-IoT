import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';

class RealtimeChart extends ConsumerWidget {
  final String field;
  const RealtimeChart({super.key, required this.field});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(metricsProvider);
    return metricsAsync.when(
      data: (metrics) {
        final data = metrics.take(30).toList().reversed.toList();
        List<FlSpot> spots = [];
        for (int i = 0; i < data.length; i++) {
          final value = _getFieldValue(data[i], field);
          spots.add(FlSpot(i.toDouble(), value));
        }
        return LineChart(
          LineChartData(
            gridData: FlGridData(show: false),
            titlesData: FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Colors.blue,
                barWidth: 2,
                dotData: FlDotData(show: false),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro ao carregar gráfico: $e')),
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
