import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_stream_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metric_provider.dart';
import 'dashboard_tabs.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    ref.watch(mqttMetricSaverProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final mqttStream = ref.watch(mqttStreamProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode 
                ? [const Color(0xFF1A202C), const Color(0xFF0F1419).withValues(alpha: 0.9)]
                : [const Color(0xFFFFFFFF), const Color(0xFFF5F7FA).withValues(alpha: 0.95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            Icon(Icons.bolt, color: Theme.of(context).colorScheme.secondary, size: 26),
            const SizedBox(width: 8),
            Text('E-Metrics IoT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5, color: isDarkMode ? Colors.white : Colors.black87)),
          ],
        ),
        centerTitle: false,
        foregroundColor: isDarkMode ? Colors.white : Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: mqttStream.when(
              data: (_) => Icon(Icons.cloud_done, color: Theme.of(context).colorScheme.secondary, size: 24),
              loading: () => Icon(Icons.cloud_queue, color: Theme.of(context).colorScheme.secondary, size: 24),
              error: (error, stackTrace) => const Icon(Icons.cloud_off, color: Colors.red, size: 24),
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
              label: 'Energia',
              value: formatWithSIPrefix(energy, fractionDigits: 3),
              icon: Icons.battery_charging_full_outlined,
              color: Color(0xFF7DF9FF),
              compact: true,
              unit: 'kWh',
            ),
            _IndicatorCard(
              label: 'Freq.',
              value: '--',
              icon: Icons.ssid_chart,
              color: Color(0xFF69F0AE),
              compact: true,
              unit: 'Hz',
            ),
          ],
        ),
      ],
    );
  }
}


class _IndicatorCard extends StatefulWidget {
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
  State<_IndicatorCard> createState() => _IndicatorCardState();
}

class _IndicatorCardState extends State<_IndicatorCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = Theme.of(context).cardColor;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Semantics(
        label: 'Indicador de ${widget.label}: ${widget.value}',
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: widget.compact ? 2 : 6,
            vertical: widget.compact ? 2 : 8,
          ),
          width: widget.compact ? 80 : 120,
          padding: EdgeInsets.symmetric(
            vertical: widget.compact ? 8 : 16,
            horizontal: widget.compact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: widget.color,
                size: widget.compact ? 24 : 30,
                semanticLabel: 'Ícone de ${widget.label}',
              ),
              SizedBox(height: widget.compact ? 4 : 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.compact ? 12 : 15,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: widget.compact ? 2 : 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.value,
                    style: TextStyle(
                      fontSize: widget.compact ? 15 : 20,
                      fontWeight: FontWeight.bold,
                      color: widget.color,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.unit != null) ...[
                    const SizedBox(width: 3),
                    Padding(
                      padding: EdgeInsets.only(bottom: widget.compact ? 1 : 2),
                      child: Text(
                        widget.unit!,
                        style: TextStyle(
                          fontSize: widget.compact ? 10 : 13,
                          color: isDarkMode
                              ? Colors.white70
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
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
