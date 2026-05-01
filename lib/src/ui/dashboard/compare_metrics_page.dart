import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/metric_model.dart';
import '../../providers/metric_provider.dart';
import 'dashboard_page.dart';

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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final meta1 = _fieldMeta(_field1);
    final meta2 = _fieldMeta(_field2);

    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDarkMode
          ? [const Color(0xFF1F2A40), const Color(0xFF1A2436)]
          : [const Color(0xFFF8FAFF), const Color(0xFFEFF4FF)],
    );

    final axisTextColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.5)
      : Colors.black.withValues(alpha: 0.4);
    final horizontalGridColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.04);
    final verticalGridColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.black.withValues(alpha: 0.025);
    return Scaffold(
      appBar: AppBar(title: const Text('Comparativo de Métricas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 12),
            Expanded(
              child: metricsAsync.when(
                data: (metrics) {
                  final data = metrics.take(40).toList().reversed.toList();
                  final last1 = data.isNotEmpty ? _getFieldValue(data.last, _field1) : null;
                  final last2 = data.isNotEmpty ? _getFieldValue(data.last, _field2) : null;

                  return Container(
                    decoration: BoxDecoration(
                      gradient: cardGradient,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Color.lerp(meta1.color, meta2.color, 0.5)!.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.28 : 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _LegendPill(
                                color: meta1.color,
                                label:
                                    '${meta1.title}: ${last1 != null ? formatWithSIPrefix(last1) : '--'}${meta1.unit.isNotEmpty ? ' ${meta1.unit}' : ''}',
                              ),
                              _LegendPill(
                                color: meta2.color,
                                label:
                                    '${meta2.title}: ${last2 != null ? formatWithSIPrefix(last2) : '--'}${meta2.unit.isNotEmpty ? ' ${meta2.unit}' : ''}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: data.isEmpty
                                ? _ChartEmptyState(textColor: axisTextColor)
                                : _buildPlot(
                                    data: data,
                                    meta1: meta1,
                                    meta2: meta2,
                                    axisTextColor: axisTextColor,
                                    horizontalGridColor: horizontalGridColor,
                                    verticalGridColor: verticalGridColor,
                                  ),
                          ),
                        ],
                      ),
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

  Widget _buildPlot({
    required List<Metric> data,
    required _FieldMeta meta1,
    required _FieldMeta meta2,
    required Color axisTextColor,
    required Color horizontalGridColor,
    required Color verticalGridColor,
  }) {
    final spots1 = [
      for (int i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), _getFieldValue(data[i], _field1)),
    ];
    final spots2 = [
      for (int i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), _getFieldValue(data[i], _field2)),
    ];
    final allSpots = [...spots1, ...spots2];
    final scale = _computeScale(allSpots, _field1 == 'pf' && _field2 == 'pf');
    final labelStep = data.length > 6 ? ((data.length - 1) / 4).ceil() : 1;
    final verticalInterval =
        data.length > 4 ? ((data.length - 1) / 4).ceilToDouble() : 1.0;
    final blendedColor =
        Color.lerp(meta1.color, meta2.color, 0.5)!.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: LineChart(
        LineChartData(
            backgroundColor: Colors.transparent,
            minX: 0,
            maxX: data.length > 1 ? (data.length - 1).toDouble() : 1,
            minY: scale.minY,
            maxY: scale.maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: scale.horizontalInterval,
              verticalInterval: verticalInterval,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: horizontalGridColor, strokeWidth: 0.6),
              getDrawingVerticalLine: (value) =>
                  FlLine(color: verticalGridColor, strokeWidth: 0.6),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  interval: scale.horizontalInterval,
                  getTitlesWidget: (value, metaData) => Text(
                    formatWithSIPrefix(value, fractionDigits: 1),
                    style: TextStyle(color: axisTextColor, fontSize: 11),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: verticalInterval,
                  getTitlesWidget: (value, metaData) => Text(
                    _buildBottomLabel(value, data, labelStep),
                    style: TextStyle(color: axisTextColor, fontSize: 11),
                  ),
                ),
              ),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border(
                left: BorderSide(color: blendedColor.withValues(alpha: 0.5), width: 1.0),
                bottom: BorderSide(color: blendedColor.withValues(alpha: 0.5), width: 1.0),
                right: BorderSide.none,
                top: BorderSide.none,
              ),
            ),
            lineTouchData: LineTouchData(
              enabled: true,
              handleBuiltInTouches: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipRoundedRadius: 10,
                tooltipPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                tooltipBorder:
                    BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 1),
                tooltipBgColor: Colors.black.withValues(alpha: 0.82),
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final index = spot.x.toInt().clamp(0, data.length - 1);
                    final time = _formatTime(data[index].timestamp);
                    final spotMeta = spot.barIndex == 0 ? meta1 : meta2;
                    final value = formatWithSIPrefix(spot.y, fractionDigits: 1);
                    final unitText = spotMeta.unit.isEmpty ? '' : ' ${spotMeta.unit}';
                    return LineTooltipItem(
                      '${spotMeta.title}: $value$unitText\n',
                      TextStyle(
                        color: spotMeta.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(
                          text: time,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots1,
                isCurved: true,
                preventCurveOverShooting: true,
                curveSmoothness: 0.24,
                color: meta1.color,
                barWidth: 2.8,
                isStrokeCapRound: true,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: meta1.color.withValues(alpha: 0.11),
                ),
              ),
              LineChartBarData(
                spots: spots2,
                isCurved: true,
                preventCurveOverShooting: true,
                curveSmoothness: 0.24,
                color: meta2.color,
                barWidth: 2.8,
                isStrokeCapRound: true,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: meta2.color.withValues(alpha: 0.11),
                ),
              ),
            ],
          ),
        ),
    );
  }

  _FieldMeta _fieldMeta(String selectedField) {
    switch (selectedField) {
      case 'voltage':
        return const _FieldMeta('Tensão', 'V', Color(0xFF3B82F6));
      case 'current':
        return const _FieldMeta('Corrente', 'A', Color(0xFF06B6D4));
      case 'power':
        return const _FieldMeta('Potência', 'W', Color(0xFFF59E0B));
      case 'pf':
        return const _FieldMeta('Fator Potência', '', Color(0xFF6366F1));
      case 'frequency':
        return const _FieldMeta('Frequência', 'Hz', Color(0xFF22C55E));
      case 'energy':
        return const _FieldMeta('Energia', 'kWh', Color(0xFF8B5CF6));
      default:
        return _FieldMeta(selectedField, '', Colors.blueGrey);
    }
  }

  double _getFieldValue(Metric metric, String selectedField) {
    switch (selectedField) {
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

  _AxisScale _computeScale(List<FlSpot> spots, bool allPf) {
    if (spots.isEmpty) {
      return const _AxisScale(0, 10, 2);
    }

    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final spot in spots.skip(1)) {
      if (spot.y < minY) {
        minY = spot.y;
      }
      if (spot.y > maxY) {
        maxY = spot.y;
      }
    }

    if (allPf) {
      final normalizedMin = minY.clamp(0.0, 1.0);
      final normalizedMax = maxY.clamp(0.0, 1.0);
      final paddedMin = (normalizedMin - 0.05).clamp(0.0, 1.0);
      final paddedMax = (normalizedMax + 0.05).clamp(0.0, 1.0);
      final safeMax = paddedMax <= paddedMin ? (paddedMin + 0.1).clamp(0.0, 1.0) : paddedMax;
      final interval = ((safeMax - paddedMin) / 4).clamp(0.05, 0.25);
      return _AxisScale(paddedMin, safeMax, interval.toDouble());
    }

    final range = maxY - minY;
    final fallbackPadding = maxY.abs() < 1 ? 1.0 : maxY.abs() * 0.08;
    final padding = range <= 0 ? fallbackPadding : range * 0.15;
    final paddedMin = minY - padding;
    final paddedMax = maxY + padding;
    final safeMax = paddedMax <= paddedMin ? paddedMin + 1 : paddedMax;
    final interval = (safeMax - paddedMin) / 4;

    return _AxisScale(
      paddedMin,
      safeMax,
      interval > 0 ? interval : 1,
    );
  }

  String _buildBottomLabel(double value, List<Metric> data, int labelStep) {
    final index = value.toInt();
    if (index < 0 || index >= data.length) {
      return '';
    }
    if (index % labelStep != 0 && index != data.length - 1) {
      return '';
    }
    return _formatTime(data[index].timestamp);
  }

  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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

class _LegendPill extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FieldMeta {
  final String title;
  final String unit;
  final Color color;

  const _FieldMeta(this.title, this.unit, this.color);
}

class _AxisScale {
  final double minY;
  final double maxY;
  final double horizontalInterval;

  const _AxisScale(this.minY, this.maxY, this.horizontalInterval);
}

class _ChartEmptyState extends StatelessWidget {
  final Color textColor;

  const _ChartEmptyState({required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_outlined, color: textColor, size: 22),
          const SizedBox(height: 6),
          Text(
            'Sem dados para plotar',
            style: TextStyle(color: textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
