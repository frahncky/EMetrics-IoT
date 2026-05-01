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
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected,
        dropdownColor: const Color(0xFF232A34),
        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.amber),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        items: fields.map((field) {
          return DropdownMenuItem<String>(
            value: field['value'],
            child: Text(field['label']!, style: const TextStyle(color: Colors.white)),
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
  String? _requestStatus;

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
    setState(() {
      _isRequesting = true;
      _requestStatus = null;
    });

    try {
      final mqttService = ref.read(mqttServiceProvider);
      await mqttService.requestHistory(from: range.$1, to: range.$2);

      setState(() {
        _requestStatus = 'Solicitação enviada ao medidor. Os gráficos serão atualizados conforme os dados chegarem.';
      });

      ref.invalidate(
        metricsByRangeProvider(
          MetricsRangeQuery(
            from: _activeFrom.millisecondsSinceEpoch,
            to: _activeTo.millisecondsSinceEpoch,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _requestStatus = 'Falha ao solicitar histórico: $e';
      });
    } finally {
      setState(() {
        _isRequesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Consumo')),
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
                const Icon(Icons.schedule, size: 16, color: Colors.white60),
                const SizedBox(width: 6),
                Text(
                  'Periodo: ${_formatDateTime(_activeFrom)} ate ${_formatDateTime(_activeTo)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRequesting ? null : _requestHistoryFromMeter,
                icon: const Icon(Icons.download),
                label: Text(_isRequesting ? 'Solicitando histórico...' : 'Solicitar histórico do medidor'),
              ),
            ),
          ),
          if (_requestStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                _requestStatus!,
                style: TextStyle(
                  color: _requestStatus!.startsWith('Falha') ? Colors.redAccent : Colors.white70,
                  fontSize: 13,
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
                        if (metrics.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Sem dados no período selecionado. Solicitando ao medidor pode preencher os gráficos.',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        Expanded(
                          child: HistoryChart(
                            metrics: metrics,
                            field: _selectedField1,
                            fieldSelector: (context) => _HistoryChartSelector(
                              selected: _selectedField1,
                              onChanged: (f) => setState(() => _selectedField1 = f),
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
}
