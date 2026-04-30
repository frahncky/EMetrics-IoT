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
  // Por padrão, mostrar o gráfico de Potência Ativa (W)
  String _selectedField = 'power';

  @override
  Widget build(BuildContext context) {
    ref.watch(mqttMetricSaverProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final mqttStream = ref.watch(mqttStreamProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF181D23),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFFFC300), size: 28),
            const SizedBox(width: 8),
            const Text('E-Metrics IoT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 0.5, color: Colors.white)),
          ],
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFF232A34),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: mqttStream.when(
              data: (_) => const Icon(Icons.cloud_done, color: Color(0xFF00C2FF), size: 26),
              loading: () => const Icon(Icons.cloud_queue, color: Color(0xFFFFC300), size: 26),
              error: (_, __) => const Icon(Icons.cloud_off, color: Colors.red, size: 26),
            ),
          ),
        ],
      ),
      drawer: const DashboardDrawer(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            metricsAsync.when(
              data: (metrics) {
                final last = metrics.isNotEmpty ? metrics.first : null;
                return Padding(
                  padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 0),
                  child: _MainIndicators(
                    voltage: last?.voltage ?? 0,
                    current: last?.current ?? 0,
                    power: last?.power ?? 0,
                    energy: last?.energy ?? 0,
                    pf: last?.pf ?? 0,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro ao carregar dados: $e', style: TextStyle(color: Color(0xFFFFC300)))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ChartSelector(
                selected: _selectedField,
                onChanged: (f) => setState(() => _selectedField = f),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                child: RealtimeChart(field: _selectedField),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: mqttStream.when(
                data: (messages) => Text(
                  'Última mensagem MQTT: ${messages.isNotEmpty ? messages.last.payload.toString() : "Nenhuma"}',
                  style: const TextStyle(color: Color(0xFF00C2FF), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text('Erro MQTT: $e', style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MainIndicators extends StatelessWidget {
  final double voltage;
  final double current;
  final double power;
  final double energy;
  final double pf;
  const _MainIndicators({
    this.voltage = 0,
    this.current = 0,
    this.power = 0,
    this.energy = 0,
    this.pf = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _IndicatorCard(
              label: 'Potência',
              value: '${power.toStringAsFixed(2)} W',
              icon: Icons.flash_on_outlined,
              color: Color(0xFFFFC300),
            ),
            _IndicatorCard(
              label: 'Corrente',
              value: '${current.toStringAsFixed(2)} A',
              icon: Icons.bolt_outlined,
              color: Color(0xFF00C2FF),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _IndicatorCard(
              label: 'Energia',
              value: '${energy.toStringAsFixed(3)} kWh',
              icon: Icons.battery_charging_full_outlined,
              color: Color(0xFF7DF9FF),
            ),
            _IndicatorCard(
              label: 'Fator Potência',
              value: pf.isNaN ? '--' : pf.toStringAsFixed(2),
              icon: Icons.speed_outlined,
              color: Color(0xFFB388FF),
            ),
          ],
        ),
      ],
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _IndicatorCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Indicador de $label: $value',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF232A34),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 30, semanticLabel: 'Ícone de $label'),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
