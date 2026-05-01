import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../data/metric_model.dart';


typedef FieldSelectorBuilder = Widget Function(BuildContext context);

class HistoryChart extends StatelessWidget {
  final List<Metric> metrics;
  final String field;
  final FieldSelectorBuilder? fieldSelector;
  const HistoryChart({super.key, required this.metrics, required this.field, this.fieldSelector});

  @override
  Widget build(BuildContext context) {
    List<FlSpot> spots = [];
    for (int i = 0; i < metrics.length; i++) {
      final value = _getFieldValue(metrics[i], field);
      spots.add(FlSpot(i.toDouble(), value));
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF232A34),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                fieldSelector != null
                    ? fieldSelector!(context)
                    : Text(_getTitle(field), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.amber)),
              ],
            ),
            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  backgroundColor: const Color(0xFF232A34),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 2,
                    verticalInterval: 2,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.18), strokeWidth: 1.2),
                    getDrawingVerticalLine: (value) => FlLine(color: Colors.white.withOpacity(0.15), strokeWidth: 1.2),
                  ),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: spots.isEmpty
                      ? [
                          LineChartBarData(
                            spots: [const FlSpot(0, 0), const FlSpot(1, 0)],
                            isCurved: true,
                            color: Colors.amber.withOpacity(0.3),
                            barWidth: 2.5,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: Colors.amber.withOpacity(0.08)),
                          ),
                        ]
                      : [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: Colors.amber,
                            barWidth: 2.5,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: Colors.amber.withOpacity(0.10)),
                          ),
                        ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getFieldValue(Metric m, String field) {
    switch (field) {
      case 'power':
        return m.power;
      case 'current':
        return m.current;
      case 'voltage':
        return m.voltage;
      case 'energy':
        return m.energy;
      default:
        return 0;
    }
  }

  String _getTitle(String field) {
    switch (field) {
      case 'power':
        return 'Potência (W)';
      case 'current':
        return 'Corrente (A)';
      case 'voltage':
        return 'Tensão (V)';
      case 'energy':
        return 'Energia (kWh)';
      default:
        return field;
    }
  }
}
