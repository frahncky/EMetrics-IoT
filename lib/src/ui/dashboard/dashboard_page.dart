import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_status_provider.dart';
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
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(mqttStatusProvider.notifier).syncBackgroundState();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(mqttMetricSaverProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final mqttStream = ref.watch(mqttStreamProvider);
    final mqttStatus = ref.watch(mqttStatusProvider);
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
        title: Row(
          children: [
            Icon(
              Icons.bolt,
              color: Theme.of(context).colorScheme.secondary,
              size: 26,
            ),
            const SizedBox(width: 8),
            Text(
              'E-Metrics IoT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        centerTitle: false,
        foregroundColor: isDarkMode ? Colors.white : Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: mqttStream.when(
              data: (_) => Icon(
                Icons.cloud_done,
                color: Theme.of(context).colorScheme.secondary,
                size: 24,
              ),
              loading: () => Icon(
                Icons.cloud_queue,
                color: Theme.of(context).colorScheme.secondary,
                size: 24,
              ),
              error: (error, stackTrace) =>
                  const Icon(Icons.cloud_off, color: Colors.red, size: 24),
            ),
          ),
        ],
      ),
      // Drawer removido
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _OperationalStatusBanner(
                status: mqttStatus,
                metricsAsync: metricsAsync,
              ),
            ),
            metricsAsync.when(
              data: (metrics) {
                final last = metrics.isNotEmpty ? metrics.first : null;
                return Padding(
                  padding: const EdgeInsets.only(
                    top: 8,
                    left: 8,
                    right: 8,
                    bottom: 0,
                  ),
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
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar dados: $e',
                  style: TextStyle(color: Color(0xFFFFC300)),
                ),
              ),
            ),
            // Dois gráficos em abas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  8,
                  0,
                  8,
                  16,
                ), // Espaço inferior para afastar do menu
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

class _OperationalStatusBanner extends StatelessWidget {
  final MqttStatusState status;
  final AsyncValue<List<dynamic>> metricsAsync;

  const _OperationalStatusBanner({
    required this.status,
    required this.metricsAsync,
  });

  @override
  Widget build(BuildContext context) {
    final lastMetricTime = metricsAsync.asData?.value.isNotEmpty == true
        ? (metricsAsync.asData!.value.first as dynamic).timestamp as DateTime
        : null;
    final chips = [
      _StatusChip(
        label: 'MQTT: ${_phaseLabel(status.phase)}',
        color: _phaseColor(status.phase),
      ),
      _StatusChip(
        label: status.backgroundActive ? 'Segundo plano ativo' : 'Segundo plano inativo',
        color: status.backgroundActive
            ? const Color(0xFF15803D)
            : const Color(0xFF64748B),
      ),
      _StatusChip(
        label: lastMetricTime != null
            ? 'Última leitura ${_relativeTime(lastMetricTime)}'
            : 'Sem leitura recente',
        color: lastMetricTime != null
            ? const Color(0xFF2563EB)
            : const Color(0xFFD97706),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saúde do monitoramento',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            if (status.lastMessage != null) ...[
              const SizedBox(height: 8),
              Text(status.lastMessage!),
            ],
          ],
        ),
      ),
    );
  }

  static Color _phaseColor(MqttConnectionPhase phase) {
    switch (phase) {
      case MqttConnectionPhase.connected:
        return const Color(0xFF15803D);
      case MqttConnectionPhase.connecting:
        return const Color(0xFFD97706);
      case MqttConnectionPhase.error:
        return const Color(0xFFDC2626);
      case MqttConnectionPhase.disconnected:
        return const Color(0xFF64748B);
    }
  }

  static String _phaseLabel(MqttConnectionPhase phase) {
    switch (phase) {
      case MqttConnectionPhase.connected:
        return 'conectado';
      case MqttConnectionPhase.connecting:
        return 'conectando';
      case MqttConnectionPhase.error:
        return 'erro';
      case MqttConnectionPhase.disconnected:
        return 'desconectado';
    }
  }

  static String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) {
      return 'há instantes';
    }
    if (difference.inHours < 1) {
      return 'há ${difference.inMinutes} min';
    }
    return 'há ${difference.inHours} h';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
    final double apparent = voltage * current;
    final double reativa = (voltage * current) * (1 - (pf.isNaN ? 0 : pf));
    const spacing = 8.0;
    final cards = [
      _IndicatorCard(
        label: 'Aparente',
        value: formatWithSIPrefix(apparent),
        icon: Icons.data_usage,
        color: const Color(0xFF10B981),
        compact: true,
        unit: 'VA',
      ),
      _IndicatorCard(
        label: 'Ativa',
        value: formatWithSIPrefix(power),
        icon: Icons.flash_on_outlined,
        color: const Color(0xFFF59E0B),
        compact: true,
        unit: 'W',
      ),
      _IndicatorCard(
        label: 'Reativa',
        value: formatWithSIPrefix(reativa),
        icon: Icons.waves,
        color: const Color(0xFF0EA5E9),
        compact: true,
        unit: 'VAr',
      ),
      _IndicatorCard(
        label: 'FP',
        value: pf.isNaN ? '--' : pf.toStringAsFixed(2),
        icon: Icons.speed_outlined,
        color: const Color(0xFF6366F1),
        compact: true,
        extraCompact: true,
      ),
      _IndicatorCard(
        label: 'Tensão',
        value: formatWithSIPrefix(voltage, fractionDigits: 1),
        icon: Icons.electrical_services,
        color: const Color(0xFF3B82F6),
        compact: true,
        unit: 'V',
      ),
      _IndicatorCard(
        label: 'Corrente',
        value: formatWithSIPrefix(current),
        icon: Icons.bolt_outlined,
        color: const Color(0xFF06B6D4),
        compact: true,
        unit: 'A',
      ),
      _IndicatorCard(
        label: 'Energia',
        value: formatWithSIPrefix(energy, fractionDigits: 3),
        icon: Icons.battery_charging_full_outlined,
        color: const Color(0xFF8B5CF6),
        compact: true,
        unit: 'kWh',
      ),
      _IndicatorCard(
        label: 'Frequência',
        value: '--',
        icon: Icons.ssid_chart,
        color: const Color(0xFF22C55E),
        compact: true,
        extraCompact: true,
        unit: 'Hz',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const columns = 4;
        final cardWidth = (maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _IndicatorCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;
  final bool extraCompact;
  final String? unit;

  const _IndicatorCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
    this.extraCompact = false,
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
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController);
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
    final isExtraCompact = widget.extraCompact && widget.compact;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Semantics(
        label: 'Indicador de ${widget.label}: ${widget.value}',
        child: Align(
          alignment: Alignment.center,
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: widget.compact ? 2 : 6,
              vertical: widget.compact ? 2 : 8,
            ),
            width: double.infinity,
            constraints: BoxConstraints(minHeight: widget.compact ? 90 : 128),
            padding: EdgeInsets.symmetric(
              vertical: isExtraCompact ? 6 : (widget.compact ? 8 : 16),
              horizontal: isExtraCompact ? 6 : (widget.compact ? 8 : 10),
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
                  size: isExtraCompact ? 20 : (widget.compact ? 24 : 30),
                  semanticLabel: 'Ícone de ${widget.label}',
                ),
                SizedBox(height: isExtraCompact ? 3 : (widget.compact ? 4 : 8)),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: isExtraCompact ? 11 : (widget.compact ? 12 : 15),
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isExtraCompact ? 1 : (widget.compact ? 2 : 6)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.value,
                        style: TextStyle(
                          fontSize: isExtraCompact
                              ? 14
                              : (widget.compact ? 16 : 20),
                          fontWeight: FontWeight.bold,
                          color: widget.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.unit != null) ...[
                        const SizedBox(width: 3),
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: isExtraCompact ? 0 : (widget.compact ? 1 : 2),
                          ),
                          child: Text(
                            widget.unit!,
                            style: TextStyle(
                              fontSize: isExtraCompact
                                  ? 9
                                  : (widget.compact ? 10 : 13),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
