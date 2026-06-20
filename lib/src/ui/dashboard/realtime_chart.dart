import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;

import '../../data/metric_model.dart';
import '../../providers/metric_provider.dart';
import '../shared/chart_metric_values.dart';

typedef FieldSelectorBuilder = Widget Function(BuildContext context);

class RealtimeChart extends ConsumerWidget {
  final String field;
  final FieldSelectorBuilder? fieldSelector;
  final bool showExpandButton;

  const RealtimeChart({
    super.key,
    required this.field,
    this.fieldSelector,
    this.showExpandButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(metricsProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final meta = _fieldMeta(field);

    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDarkMode
          ? [const Color(0xFF1F2A40), const Color(0xFF1A2436)]
          : [const Color(0xFFF8FAFF), const Color(0xFFEFF4FF)],
    );

    final titleColor = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    final axisTextColor = meta.color.withValues(alpha: isDarkMode ? 0.9 : 0.96);
    final horizontalGridColor = meta.color.withValues(
      alpha: isDarkMode ? 0.22 : 0.18,
    );
    final verticalGridColor = meta.color.withValues(
      alpha: isDarkMode ? 0.14 : 0.11,
    );

    return metricsAsync.when(
      data: (metrics) {
        final data = metrics.take(30).toList().reversed.toList();
        final hasData = data.isNotEmpty;
        final values = chartValuesForField(data, field);
        final spots = [
          for (int i = 0; i < data.length; i++) FlSpot(i.toDouble(), values[i]),
        ];
        final chartSpots = hasData ? spots : const [FlSpot(0, 0), FlSpot(6, 0)];
        final unitScale = _computeUnitScale(spots, field, meta.unit);
        final scale = hasData
            ? _computeScale(spots, field, unitScale)
            : const _AxisScale(-1, 1, 0.5);
        final displayUnit = _buildDisplayUnit(meta.unit, unitScale.prefix);
        final displayInterval = scale.horizontalInterval / unitScale.divisor;
        final labelStep = hasData
            ? (data.length > 6 ? ((data.length - 1) / 4).ceil() : 1)
            : 1;
        final verticalInterval = hasData
            ? (data.length > 4 ? ((data.length - 1) / 4).ceilToDouble() : 1.0)
            : 1.0;
        final lastValue = hasData ? values.last : null;

        return Container(
          decoration: BoxDecoration(
            gradient: cardGradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: meta.color.withValues(alpha: 0.45),
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
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeader = constraints.maxWidth < 360;
                    final currentValue =
                        '${lastValue != null ? _formatScaledValue(lastValue, unitScale, field == 'pf') : '--'}${displayUnit.isNotEmpty ? ' $displayUnit' : ''}';
                    final currentLabel = compactHeader
                        ? currentValue
                        : 'Instantâneo: $currentValue';

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: fieldSelector != null
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        fieldSelector!(context),
                                        if (displayUnit.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '($displayUnit)',
                                            style: TextStyle(
                                              color: titleColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : Text(
                                      '${meta.title} ${displayUnit.isNotEmpty ? '($displayUnit)' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: titleColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: meta.color.withValues(
                                  alpha: isDarkMode ? 0.18 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: meta.color.withValues(alpha: 0.42),
                                  width: 1.1,
                                ),
                              ),
                              child: Text(
                                currentLabel,
                                maxLines: 1,
                                style: TextStyle(
                                  color: meta.color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            if (showExpandButton) ...[
                              const SizedBox(width: 2),
                              IconButton(
                                tooltip: 'Expandir gráfico',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 30,
                                  height: 30,
                                ),
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                color: meta.color,
                                onPressed: () => _openExpandedChart(context),
                                icon: const Icon(Icons.open_in_full),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        LineChart(
                          LineChartData(
                            backgroundColor: Colors.transparent,
                            minX: 0,
                            maxX: hasData
                                ? (chartSpots.length > 1
                                      ? (chartSpots.length - 1).toDouble()
                                      : 1)
                                : 6,
                            minY: scale.minY,
                            maxY: scale.maxY,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              horizontalInterval: scale.horizontalInterval,
                              verticalInterval: verticalInterval,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: horizontalGridColor,
                                strokeWidth: 0.9,
                              ),
                              getDrawingVerticalLine: (value) => FlLine(
                                color: verticalGridColor,
                                strokeWidth: 0.8,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 38,
                                  interval: scale.horizontalInterval,
                                  getTitlesWidget: (value, meta) =>
                                      SideTitleWidget(
                                        axisSide: meta.axisSide,
                                        fitInside:
                                            SideTitleFitInsideData.fromTitleMeta(
                                              meta,
                                              distanceFromEdge: 4,
                                            ),
                                        child: Text(
                                          _formatScaledValue(
                                            value,
                                            unitScale,
                                            field == 'pf',
                                            displayInterval,
                                          ),
                                          style: TextStyle(
                                            color: axisTextColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 22,
                                  interval: verticalInterval,
                                  getTitlesWidget: (value, meta) {
                                    final label = hasData
                                        ? _buildBottomLabel(
                                            value,
                                            data,
                                            labelStep,
                                          )
                                        : value.toInt().toString();
                                    return SideTitleWidget(
                                      axisSide: meta.axisSide,
                                      fitInside:
                                          SideTitleFitInsideData.fromTitleMeta(
                                            meta,
                                            distanceFromEdge: 4,
                                          ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: axisTextColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border(
                                left: BorderSide(
                                  color: meta.color.withValues(alpha: 0.56),
                                  width: 1.0,
                                ),
                                bottom: BorderSide(
                                  color: meta.color.withValues(alpha: 0.56),
                                  width: 1.0,
                                ),
                                right: BorderSide.none,
                                top: BorderSide.none,
                              ),
                            ),
                            lineTouchData: LineTouchData(
                              enabled: hasData,
                              handleBuiltInTouches: true,
                              touchTooltipData: LineTouchTooltipData(
                                tooltipRoundedRadius: 10,
                                tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                tooltipBorder: BorderSide(
                                  color: meta.color.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                                tooltipBgColor: Colors.black.withValues(
                                  alpha: 0.82,
                                ),
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final index = spot.x.toInt().clamp(
                                      0,
                                      data.length - 1,
                                    );
                                    final time = _formatTime(
                                      data[index].timestamp,
                                    );
                                    final value = _formatScaledValue(
                                      spot.y,
                                      unitScale,
                                      field == 'pf',
                                    );
                                    final unitText = displayUnit.isEmpty
                                        ? ''
                                        : ' $displayUnit';
                                    return LineTooltipItem(
                                      '$value$unitText\n',
                                      TextStyle(
                                        color: meta.color,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: time,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
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
                                spots: chartSpots,
                                isCurved: true,
                                preventCurveOverShooting: true,
                                curveSmoothness: 0.24,
                                color: hasData
                                    ? meta.color
                                    : Colors.transparent,
                                barWidth: hasData ? 3.6 : 0,
                                isStrokeCapRound: true,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: hasData,
                                  color: meta.color.withValues(alpha: 0.16),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!hasData)
                          Text(
                            'Sem dados',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
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
      error: (e, _) => Center(
        child: Text(
          'Erro ao carregar gráfico: $e',
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }

  _FieldMeta _fieldMeta(String selectedField) {
    switch (selectedField) {
      case 'power':
      case 'power_active':
        return const _FieldMeta('Potência Ativa', 'W', Color(0xFFF59E0B));
      case 'power_apparent':
        return const _FieldMeta('Potência Aparente', 'VA', Color(0xFF38BDF8));
      case 'power_reactive':
        return const _FieldMeta('Potência Reativa', 'VAr', Color(0xFFF97316));
      case 'current':
        return const _FieldMeta('Corrente', 'A', Color(0xFF7AAEFF));
      case 'voltage':
        return const _FieldMeta('Tensão', 'V', Color(0xFFE2B93B));
      case 'energy':
      case 'energy_active':
        return const _FieldMeta('Energia Ativa', 'kWh', Color(0xFF8B5CF6));
      case 'energy_apparent':
        return const _FieldMeta('Energia Aparente', 'kVAh', Color(0xFF38BDF8));
      case 'energy_reactive':
        return const _FieldMeta('Energia Reativa', 'kVArh', Color(0xFFF97316));
      case 'pf':
        return const _FieldMeta('Fator de potência', '', Color(0xFF9D8CFF));
      case 'frequency':
        return const _FieldMeta('Frequência', 'Hz', Color(0xFF22C55E));
      default:
        return _FieldMeta(selectedField, '', Colors.blueAccent);
    }
  }

  _AxisScale _computeScale(
    List<FlSpot> spots,
    String selectedField,
    _UnitScale unitScale,
  ) {
    if (spots.isEmpty) {
      return const _AxisScale(-1, 1, 0.5);
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

    if (selectedField == 'pf') {
      final normalizedMin = minY.clamp(0.0, 1.0);
      final normalizedMax = maxY.clamp(0.0, 1.0);
      final paddedMin = (normalizedMin - 0.05).clamp(0.0, 1.0);
      final paddedMax = (normalizedMax + 0.05).clamp(0.0, 1.0);
      final safeMax = paddedMax <= paddedMin
          ? (paddedMin + 0.1).clamp(0.0, 1.0)
          : paddedMax;
      final interval = ((safeMax - paddedMin) / 4).clamp(0.05, 0.25);
      return _AxisScale(paddedMin, safeMax, interval.toDouble());
    }

    // A grade deve ser calculada na unidade que será exibida. Caso contrário,
    // uma variação muito pequena pode gerar ticks diferentes com o mesmo texto.
    final minDisplayValue = minY / unitScale.divisor;
    final maxDisplayValue = maxY / unitScale.divisor;
    final range = maxDisplayValue - minDisplayValue;
    final fallbackPadding = maxDisplayValue.abs() < 1
        ? 1.0
        : maxDisplayValue.abs() * 0.08;
    final padding = range <= 0 ? fallbackPadding : range * 0.15;
    final paddedMin = minDisplayValue - padding;
    final paddedMax = maxDisplayValue + padding;
    final safeMax = paddedMax <= paddedMin ? paddedMin + 1 : paddedMax;
    final interval = _niceInterval(safeMax - paddedMin, 3);
    final axisMin = (paddedMin / interval).floorToDouble() * interval;
    final axisMax = (safeMax / interval).ceilToDouble() * interval;

    return _AxisScale(
      axisMin * unitScale.divisor,
      axisMax * unitScale.divisor,
      interval * unitScale.divisor,
    );
  }

  double _niceInterval(double range, int targetIntervals) {
    if (!range.isFinite || range <= 0) {
      return 1;
    }

    final rawInterval = range / targetIntervals;
    final magnitude = math
        .pow(10, (math.log(rawInterval) / math.ln10).floor())
        .toDouble();
    final normalized = rawInterval / magnitude;
    final niceNormalized = normalized <= 1
        ? 1.0
        : normalized <= 2
        ? 2.0
        : normalized <= 2.5
        ? 2.5
        : normalized <= 5
        ? 5.0
        : 10.0;
    return niceNormalized * magnitude;
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

  _UnitScale _computeUnitScale(
    List<FlSpot> spots,
    String selectedField,
    String unit,
  ) {
    if (selectedField == 'pf' || unit.isEmpty || spots.isEmpty) {
      return const _UnitScale(1, '');
    }

    var maxAbs = 0.0;
    for (final spot in spots) {
      final abs = spot.y.abs();
      if (abs > maxAbs) {
        maxAbs = abs;
      }
    }

    if (maxAbs >= 1e9) return const _UnitScale(1e9, 'G');
    if (maxAbs >= 1e6) return const _UnitScale(1e6, 'M');
    if (maxAbs >= 1e3) return const _UnitScale(1e3, 'k');
    if (maxAbs > 0 && maxAbs < 1e-3) return const _UnitScale(1e-6, 'μ');
    if (maxAbs > 0 && maxAbs < 1) return const _UnitScale(1e-3, 'm');
    return const _UnitScale(1, '');
  }

  String _buildDisplayUnit(String unit, String prefix) {
    // Energia usa unidades iniciadas em "k" (kWh, kVAh e kVArh). Concatenar
    // o prefixo diretamente criaria rótulos pouco legíveis como "mkWh".
    if (unit.startsWith('k') && unit.endsWith('h')) {
      final baseUnit = unit.substring(1);
      switch (prefix) {
        case 'm':
          return baseUnit;
        case 'μ':
          return 'm$baseUnit';
        case 'k':
          return 'M$baseUnit';
        case 'M':
          return 'G$baseUnit';
        case 'G':
          return 'T$baseUnit';
      }
    }
    if (unit.isEmpty) {
      return '';
    }
    if (prefix.isEmpty) {
      return unit;
    }
    return '$prefix$unit';
  }

  String _formatScaledValue(
    double rawValue,
    _UnitScale scale,
    bool isPf, [
    double? displayInterval,
  ]) {
    final value = rawValue / scale.divisor;
    if (isPf) {
      return value.toStringAsFixed(2);
    }
    if (displayInterval != null) {
      final fractionDigits = _fractionDigitsForInterval(displayInterval);
      final zeroThreshold = 0.5 * math.pow(10, -fractionDigits);
      final normalizedValue = value.abs() < zeroThreshold ? 0.0 : value;
      return normalizedValue.toStringAsFixed(fractionDigits);
    }
    if (value.abs() >= 100) return value.toStringAsFixed(0);
    if (value.abs() >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  int _fractionDigitsForInterval(double interval) {
    final absoluteInterval = interval.abs();
    if (!absoluteInterval.isFinite || absoluteInterval <= 0) {
      return 2;
    }

    for (var digits = 0; digits < 6; digits++) {
      final shifted = absoluteInterval * math.pow(10, digits);
      if ((shifted - shifted.round()).abs() < 1e-9) {
        return digits;
      }
    }
    return 6;
  }

  void _openExpandedChart(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ExpandedRealtimeChartPage(initialField: field),
      ),
    );
  }
}

class _ExpandedRealtimeChartPage extends StatefulWidget {
  final String initialField;

  const _ExpandedRealtimeChartPage({required this.initialField});

  @override
  State<_ExpandedRealtimeChartPage> createState() =>
      _ExpandedRealtimeChartPageState();
}

class _ExpandedRealtimeChartPageState
    extends State<_ExpandedRealtimeChartPage> {
  late String _field;

  @override
  void initState() {
    super.initState();
    _field = widget.initialField;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).cardColor;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1F2937);

    return Scaffold(
      appBar: AppBar(title: const Text('Gráfico em tela cheia')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: RealtimeChart(
            field: _field,
            showExpandButton: false,
            fieldSelector: (context) {
              return DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _field,
                  dropdownColor: backgroundColor,
                  style: TextStyle(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: colorScheme.secondary,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _field = value);
                    }
                  },
                  items: _metricFieldOptions.map((field) {
                    return DropdownMenuItem<String>(
                      value: field.value,
                      child: Text(
                        field.label,
                        style: TextStyle(color: textColor),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

const _metricFieldOptions = [
  _MetricFieldOption('voltage', 'Tensão'),
  _MetricFieldOption('current', 'Corrente'),
  _MetricFieldOption('power', 'Potência Ativa'),
  _MetricFieldOption('power_apparent', 'Potência Aparente'),
  _MetricFieldOption('power_reactive', 'Potência Reativa'),
  _MetricFieldOption('pf', 'Fator de potência'),
  _MetricFieldOption('frequency', 'Frequência'),
  _MetricFieldOption('energy_active', 'Energia Ativa'),
  _MetricFieldOption('energy_apparent', 'Energia Aparente'),
  _MetricFieldOption('energy_reactive', 'Energia Reativa'),
];

class _MetricFieldOption {
  final String value;
  final String label;

  const _MetricFieldOption(this.value, this.label);
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

class _UnitScale {
  final double divisor;
  final String prefix;

  const _UnitScale(this.divisor, this.prefix);
}
