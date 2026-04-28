import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_stream_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import 'realtime_chart.dart';
import 'chart_selector.dart';
import 'dashboard_drawer.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  String _selectedField = 'voltage';

  @override
  Widget build(BuildContext context) {
    ref.watch(mqttMetricSaverProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final mqttStream = ref.watch(mqttStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Metrics IoT'),
        actions: [
          mqttStream.when(
            data: (_) => const Icon(Icons.cloud_done, color: Colors.green),
            loading: () => const Icon(Icons.cloud_queue, color: Colors.orange),
            error: (_, __) => const Icon(Icons.cloud_off, color: Colors.red),
          ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: const DashboardDrawer(),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ChartSelector(
              selected: _selectedField,
              onChanged: (f) => setState(() => _selectedField = f),
            ),
          ),
          Expanded(
            child: metricsAsync.when(
              data: (metrics) {
                final last = metrics.isNotEmpty ? metrics.first : null;
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _MainIndicators(
                        voltage: last?.voltage ?? 0,
                        current: last?.current ?? 0,
                        power: last?.power ?? 0,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: Card(
                          color: Colors.grey[900],
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: RealtimeChart(field: _selectedField),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro ao carregar dados: $e')),
            ),
          ),
          mqttStream.when(
            data: (messages) => Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Última mensagem MQTT recebida: ${messages.isNotEmpty ? messages.last.payload.toString() : "Nenhuma"}'),
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Erro MQTT: $e'),
            ),
          ),
        ],
      ),
    );
  }
}


class _MainIndicators extends StatelessWidget {
  final double voltage;
  final double current;
  final double power;
  const _MainIndicators({this.voltage = 0, this.current = 0, this.power = 0});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _IndicatorCard(label: 'Tensão', value: '${voltage.toStringAsFixed(2)} V'),
        _IndicatorCard(label: 'Corrente', value: '${current.toStringAsFixed(2)} A'),
        _IndicatorCard(label: 'Potência', value: '${power.toStringAsFixed(2)} W'),
      ],
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final String label;
  final String value;
  const _IndicatorCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blueGrey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
