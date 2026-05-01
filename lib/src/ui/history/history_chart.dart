import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../data/metric_model.dart';
import '../dashboard/dashboard_page.dart';

typedef FieldSelectorBuilder = Widget Function(BuildContext context);

class HistoryChart extends StatelessWidget {
  final List<Metric> metrics;
  final String field;
  final FieldSelectorBuilder? fieldSelector;
  const HistoryChart({
    super.key,
    required this.metrics,
    required this.field,
    this.fieldSelector,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDarkMode = brightness == Brightness.dark;
    final gridColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final gridColorV = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.03);
    final textColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.45);
    final backgroundColor = Theme.of(context).cardColor;

    Color mainColor;
    String title;
    String unit;
    switch (field) {
      case 'power':
        mainColor = const Color(0xFFF59E0B);
        title = 'Potência';
        unit = 'W';
        break;
      case 'current':
        mainColor = const Color(0xFF06B6D4);
        title = 'Corrente';
        unit = 'A';
        break;
      case 'voltage':
        mainColor = const Color(0xFF3B82F6);
        title = 'Tensão';
        unit = 'V';
        break;
      case 'energy':
        mainColor = const Color(0xFF8B5CF6);
        title = 'Energia';
        unit = 'kWh';
        break;
      case 'pf':
        mainColor = const Color(0xFF6366F1);
        title = 'Fator Potência';
        unit = '';
        break;
      case 'frequency':
        mainColor = const Color(0xFF22C55E);
        title = 'Frequência';
        unit = 'Hz';
        break;
      default:
        mainColor = Colors.blueAccent;
        title = field;
        unit = '';
    }

    List<FlSpot> spots = [];
    final data = metrics.take(30).toList().reversed.toList();
    for (int i = 0; i < data.length; i++) {
      final value = _getFieldValue(data[i], field);
      spots.add(FlSpot(i.toDouble(), value));
    }
    final double? lastValue = data.isNotEmpty
        ? _getFieldValue(data.last, field)
        : null;
    final labelStep = data.length > 6 ? (data.length / 4).ceil() : 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                fieldSelector != null
                    ? fieldSelector!(context)
                    : Text(
                        '$title (${unit.isNotEmpty ? unit : ''})',
                        style: TextStyle(
                          color: mainColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: mainColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: mainColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Instantâneo: '
                    '${lastValue != null ? formatWithSIPrefix(lastValue) : '--'} $unit',
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
                  backgroundColor: backgroundColor,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 2,
                    verticalInterval: 2,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: gridColor, strokeWidth: 0.5),
                    getDrawingVerticalLine: (value) =>
                        FlLine(color: gridColorV, strokeWidth: 0.5),
                  ),
                  titlesData: spots.isEmpty
                      ? FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        )
                      : FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) => Text(
                                formatWithSIPrefix(value, fractionDigits: 1),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (value, meta) => Text(
                                _buildBottomLabel(value, data, labelStep),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                  borderData: FlBorderData(show: false),
                  minX: spots.isEmpty ? 0 : 0,
                  maxX: spots.isEmpty
                      ? 10
                      : (spots.length > 1 ? spots.length - 1 : 1),
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
                              color: mainColor.withValues(alpha: 0.10),
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
      case 'pf':
        return m.pf;
      case 'frequency':
        return m.frequency;
      default:
        return 0;
    }
  }

  String _buildBottomLabel(double value, List<Metric> data, int labelStep) {
    final index = value.toInt();
    if (index < 0 || index >= data.length) {
      return '';
    }
    if (index % labelStep != 0 && index != data.length - 1) {
      return '';
    }

    final timestamp = data[index].timestamp;
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
