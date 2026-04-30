import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_stream_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import 'realtime_chart.dart';
import 'chart_selector.dart';
import 'dashboard_tabs.dart';
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
        toolbarHeight: 52, // altura levemente aumentada
        title: Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFFFC300), size: 26),
            const SizedBox(width: 8),
            const Text('E-Metrics IoT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5, color: Colors.white)),
          ],
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFF232A34),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: mqttStream.when(
              data: (_) => const Icon(Icons.cloud_done, color: Color(0xFF00C2FF), size: 24),
              loading: () => const Icon(Icons.cloud_queue, color: Color(0xFFFFC300), size: 24),
              error: (_, __) => const Icon(Icons.cloud_off, color: Colors.red, size: 24),
            ),
          ),
        ],
      ),
      // Drawer removido
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
            // Dois gráficos em abas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), // Espaço inferior para afastar do menu
                child: DashboardTabs(),
              ),
            ),
            // Aviso de erro MQTT removido
          ],
        ),
      ),
    );
  }
}


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
    // Cálculos para aparente, reativa e frequência
    final double apparent = voltage * current;
    final double reativa = (voltage * current) * (1 - (pf.isNaN ? 0 : pf));
    final double? freq = null; // Será passado pelo parâmetro futuramente se necessário

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _IndicatorCard(
              label: 'Aparente',
              value: formatWithSIPrefix(apparent),
              icon: Icons.data_usage,
              color: Color(0xFF00E676),
              compact: true,
              unit: 'VA',
            ),
            _IndicatorCard(
              label: 'Ativa',
              value: formatWithSIPrefix(power),
              icon: Icons.flash_on_outlined,
              color: Color(0xFFFFC300),
              compact: true,
              unit: 'W',
            ),
            _IndicatorCard(
              label: 'Reativa',
              value: formatWithSIPrefix(reativa),
              icon: Icons.waves,
              color: Color(0xFF00B8D4),
              compact: true,
              unit: 'VAr',
            ),
            _IndicatorCard(
              label: 'FP',
              value: pf.isNaN ? '--' : pf.toStringAsFixed(2),
              icon: Icons.speed_outlined,
              color: Color(0xFFB388FF),
              compact: true,
            ),
            _IndicatorCard(
              label: 'Tensão',
              value: formatWithSIPrefix(voltage, fractionDigits: 1),
              icon: Icons.electrical_services,
              color: Color(0xFF7DF9FF),
              compact: true,
              unit: 'V',
            ),
            _IndicatorCard(
              label: 'Corrente',
              value: formatWithSIPrefix(current),
              icon: Icons.bolt_outlined,
              color: Color(0xFF00C2FF),
              compact: true,
              unit: 'A',
            ),
            _IndicatorCard(
              label: 'Freq.',
              value: '--',
              icon: Icons.ssid_chart,
              color: Color(0xFF69F0AE),
              compact: true,
              unit: 'Hz',
            ),
            _IndicatorCard(
              label: 'Energia',
              value: formatWithSIPrefix(energy, fractionDigits: 3),
              icon: Icons.battery_charging_full_outlined,
              color: Color(0xFF7DF9FF),
              compact: true,
              unit: 'kWh',
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
  final bool compact;
  final String? unit;

  const _IndicatorCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Indicador de $label: $value',
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 6, vertical: compact ? 2 : 8),
        child: Container(
          width: compact ? 80 : 120,
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16, horizontal: compact ? 4 : 8),
          decoration: BoxDecoration(
            color: const Color(0xFF232A34),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: compact ? 24 : 30, semanticLabel: 'Ícone de $label'),
              SizedBox(height: compact ? 4 : 8),
              Text(
                label,
                style: TextStyle(fontSize: compact ? 12 : 15, color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: compact ? 2 : 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(fontSize: compact ? 15 : 20, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                  if (unit != null) ...[
                    SizedBox(width: 3),
                    Padding(
                      padding: EdgeInsets.only(bottom: compact ? 1 : 2),
                      child: Text(
                        unit!,
                        style: TextStyle(fontSize: compact ? 10 : 13, color: Colors.white70, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
