import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import '../../providers/mqtt_provider.dart';
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
    return '${(value / 1e9).toStringAsFixed(d)} G';
  } else if (abs >= 1e6) {
    final d = fractionDigits ?? digits(value / 1e6);
    return '${(value / 1e6).toStringAsFixed(d)} M';
  } else if (abs >= 1e3) {
    final d = fractionDigits ?? digits(value / 1e3);
    return '${(value / 1e3).toStringAsFixed(d)} K';
  } else if (abs < 1e-3 && abs > 0) {
    final d = fractionDigits ?? digits(value * 1e6);
    return '${(value * 1e6).toStringAsFixed(d)} μ';
  } else if (abs < 1 && abs >= 1e-3) {
    final d = fractionDigits ?? digits(value * 1e3);
    return '${(value * 1e3).toStringAsFixed(d)} m';
  } else {
    final d = fractionDigits ?? digits(value.toDouble());
    return value.toStringAsFixed(d);
  }
}

// Seletor igual ao Dashboard, mas para histórico
class _HistoryChartSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _HistoryChartSelector({
    required this.selected,
    required this.onChanged,
  });

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
    final secondaryColor = Theme.of(context).colorScheme.secondary;
    final backgroundColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected,
        dropdownColor: backgroundColor,
        style: TextStyle(
          color: secondaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        icon: Icon(Icons.arrow_drop_down, color: secondaryColor),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        items: fields.map((field) {
          return DropdownMenuItem<String>(
            value: field['value'],
            child: Text(field['label']!, style: TextStyle(color: textColor)),
          );
        }).toList(),
      ),
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
  late DateTime _activeFrom;
  late DateTime _activeTo;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    final range = _rangeForPeriod(_period);
    _activeFrom = range.$1;
    _activeTo = range.$2;
  }

  (DateTime, DateTime) _rangeForPeriod(HistoryPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case HistoryPeriod.hora:
        return (now.subtract(const Duration(hours: 1)), now);
      case HistoryPeriod.dia:
        return (DateTime(now.year, now.month, now.day), now);
      case HistoryPeriod.semana:
        return (now.subtract(const Duration(days: 7)), now);
      case HistoryPeriod.mes:
        return (DateTime(now.year, now.month, 1), now);
    }
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  Future<void> _requestHistoryFromMeter() async {
    final range = (_activeFrom, _activeTo);
    final query = MetricsRangeQuery(
      from: _activeFrom.millisecondsSinceEpoch,
      to: _activeTo.millisecondsSinceEpoch,
    );
    final rangeProvider = metricsByRangeProvider(query);
    final baselineCount = ref.read(rangeProvider).asData?.value.length;

    setState(() {
      _isRequesting = true;
    });

    try {
      final mqttService = ref.read(mqttServiceProvider);
      await mqttService.requestHistory(from: range.$1, to: range.$2);

      var updated = false;
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        ref.invalidate(rangeProvider);
        final refreshed = await ref.read(rangeProvider.future);
        final hasGrowth =
            baselineCount == null || refreshed.length > baselineCount;
        if (hasGrowth || refreshed.isNotEmpty) {
          updated = true;
          break;
        }
      }

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updated
                ? 'Histórico solicitado e atualizado.'
                : 'Solicitação enviada. Aguardando novas métricas.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      final text = e.toString();
      const prefix = 'Exception: ';
      final message = text.startsWith(prefix)
          ? text.substring(prefix.length)
          : text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao solicitar histórico: $message')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final mutedTextColor = isDarkMode
        ? Colors.white70
        : colorScheme.onSurface.withValues(alpha: 0.68);
    final successTextColor = isDarkMode
        ? const Color(0xFF22C55E)
        : const Color(0xFF15803D);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [
                      const Color(0xFF1A202C),
                      const Color(0xFF0F1419).withValues(alpha: 0.9),
                    ]
                  : [
                      const Color(0xFFFFFFFF),
                      const Color(0xFFF8FAFC).withValues(alpha: 0.9),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('Histórico de Consumo'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          HistoryFilter(
            selected: _period,
            onChanged: (p) {
              final range = _rangeForPeriod(p);
              setState(() {
                _period = p;
                _activeFrom = range.$1;
                _activeTo = range.$2;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule, size: 16, color: mutedTextColor),
                const SizedBox(width: 6),
                Text(
                  'Período: ${_formatDateTime(_activeFrom)} até ${_formatDateTime(_activeTo)}',
                  style: TextStyle(color: mutedTextColor, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRequesting ? null : _requestHistoryFromMeter,
                    icon: const Icon(Icons.download),
                    label: Text(
                      _isRequesting
                          ? 'Solicitando histórico...'
                          : 'Solicitar histórico do medidor',
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ref
                .watch(
                  metricsByRangeProvider(
                    MetricsRangeQuery(
                      from: _activeFrom.millisecondsSinceEpoch,
                      to: _activeTo.millisecondsSinceEpoch,
                    ),
                  ),
                )
                .when(
                  data: (metrics) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            metrics.isEmpty
                                ? 'Sem dados no período selecionado.'
                                : 'Dados disponíveis no período selecionado.',
                            style: TextStyle(
                              color: metrics.isEmpty
                                  ? mutedTextColor
                                  : successTextColor,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: HistoryChart(
                            metrics: metrics,
                            field: _selectedField1,
                            fieldSelector: (context) => _HistoryChartSelector(
                              selected: _selectedField1,
                              onChanged: (f) =>
                                  setState(() => _selectedField1 = f),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: HistoryChart(
                            metrics: metrics,
                            field: _selectedField2,
                            fieldSelector: (context) => _HistoryChartSelector(
                              selected: _selectedField2,
                              onChanged: (f) =>
                                  setState(() => _selectedField2 = f),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('Erro ao carregar histórico: $e')),
                ),
          ),
        ],
      ),
    );
  }
}
