import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_page.dart';
import '../../providers/metric_provider.dart';

typedef FieldSelectorBuilder = Widget Function(BuildContext context);

class RealtimeChart extends ConsumerWidget {
  final String field;
  final FieldSelectorBuilder? fieldSelector;
  const RealtimeChart({super.key, required this.field, this.fieldSelector});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(metricsProvider);
    Color mainColor;
    String title;
    String unit;
    switch (field) {
      case 'power':
        mainColor = const Color(0xFFFFC300); title = 'Potência'; unit = 'W'; break;
      case 'current':
        mainColor = const Color(0xFF00C2FF); title = 'Corrente'; unit = 'A'; break;
      case 'voltage':
        mainColor = const Color(0xFF7DF9FF); title = 'Tensão'; unit = 'V'; break;
      case 'energy':
        mainColor = const Color(0xFFB388FF); title = 'Energia'; unit = 'kWh'; break;
      case 'pf':
        mainColor = const Color(0xFFB388FF); title = 'Fator Potência'; unit = ''; break;
      case 'frequency':
        mainColor = Colors.greenAccent; title = 'Frequência'; unit = 'Hz'; break;
      default:
        mainColor = Colors.blueAccent; title = field; unit = '';
    }
    return metricsAsync.when(
      data: (metrics) {
        final data = metrics.take(30).toList().reversed.toList();
        List<FlSpot> spots = [];
        for (int i = 0; i < data.length; i++) {
          final value = _getFieldValue(data[i], field);
          spots.add(FlSpot(i.toDouble(), value));
        }
        final double? lastValue = data.isNotEmpty ? _getFieldValue(data.last, field) : null;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF232A34),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: mainColor.withOpacity(0.25), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    fieldSelector != null
                        ? fieldSelector!(context)
                        : Text(
                            '$title (${unit.isNotEmpty ? unit : ''})',
                            style: TextStyle(
                              color: mainColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 0.5,
                            ),
                          ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: mainColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mainColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Instantâneo: '
                        '${lastValue != null ? formatWithSIPrefix(lastValue) : '--'} ${unit}',
                        style: TextStyle(
                          color: mainColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      backgroundColor: const Color(0xFF232A34),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 2,
                        verticalInterval: 2,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.white.withOpacity(0.18),
                          strokeWidth: 1.2,
                        ),
                        getDrawingVerticalLine: (value) => FlLine(
                          color: Colors.white.withOpacity(0.15),
                          strokeWidth: 1.2,
                        ),
                      ),
                      titlesData: spots.isEmpty
                          ? FlTitlesData(
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            )
                          : FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  getTitlesWidget: (value, meta) => Text(
                                    formatWithSIPrefix(value, fractionDigits: 1),
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  getTitlesWidget: (value, meta) => Text(
                                    value.toInt().toString(),
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                  ),
                                ),
                              ),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: mainColor.withOpacity(0.25), width: 1),
                      ),
                      minX: spots.isEmpty ? 0 : 0,
                      maxX: spots.isEmpty ? 10 : (spots.length > 1 ? spots.length - 1 : 1),
                      minY: spots.isEmpty ? 0 : null,
                      maxY: spots.isEmpty ? 10 : null,
                      lineBarsData: spots.isEmpty
                          ? [
                              LineChartBarData(
                                spots: [const FlSpot(0, 0)],
                                isCurved: false,
                                color: Colors.transparent,
                                barWidth: 0,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ]
                          : [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                color: mainColor,
                                barWidth: 2.5,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: mainColor.withOpacity(0.10),
                                ),
                              ),
                            ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro ao carregar gráfico: $e', style: TextStyle(color: Colors.redAccent))),
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
