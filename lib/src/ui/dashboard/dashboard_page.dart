import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_settings_provider.dart';
import '../../providers/mqtt_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/dashboard_preferences_provider.dart';
import '../../providers/forecast_provider.dart';
import '../../providers/metric_provider.dart';
import 'dashboard_tabs.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  Future<void> _syncBackgroundState() async {
    await ref.read(mqttStatusProvider.notifier).syncBackgroundState();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      _syncBackgroundState();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncBackgroundState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(mqttMetricSaverProvider);
    final mqttSettings = ref.watch(mqttSettingsProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final mqttStatus = ref.watch(mqttStatusProvider);
    final dashboardPreferences = ref.watch(dashboardPreferencesProvider);
    final forecastAsync = ref.watch(forecastProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final lastMetricTime = metricsAsync.asData?.value.isNotEmpty == true
        ? metricsAsync.asData!.value.first.timestamp
        : null;
    final statusVisual = _buildMonitoringStatusVisual(mqttStatus, lastMetricTime);

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'E-Metrics IoT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  mqttSettings.profileName,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode
                        ? Colors.white54
                        : Colors.black45,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
        centerTitle: false,
        foregroundColor: isDarkMode ? Colors.white : Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Tooltip(
              message: statusVisual.message,
              child: Icon(
                statusVisual.icon,
                color: statusVisual.color,
                size: 24,
              ),
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
                return Column(
                  children: [
                    Padding(
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
                    ),
                    if (dashboardPreferences.showForecastCard)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: forecastAsync.when(
                          data: (forecast) {
                            if (forecast == null) {
                              return const SizedBox.shrink();
                            }
                            return _ForecastCard(snapshot: forecast);
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ),
                  ],
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

_MonitoringStatusVisual _buildMonitoringStatusVisual(
  MqttStatusState status,
  DateTime? lastMetricTime,
) {
  final phaseLabel = _phaseLabel(status.phase);

  if (status.phase == MqttConnectionPhase.error) {
    return _MonitoringStatusVisual(
      icon: Icons.error_outline,
      color: const Color(0xFFDC2626),
      message: status.lastMessage ?? 'Monitoramento com erro.',
    );
  }

  if (status.phase == MqttConnectionPhase.connecting) {
    return _MonitoringStatusVisual(
      icon: Icons.sync,
      color: const Color(0xFFD97706),
      message: 'MQTT conectando.',
    );
  }

  if (status.phase == MqttConnectionPhase.connected) {
    if (lastMetricTime == null) {
      return _MonitoringStatusVisual(
        icon: Icons.sensors,
        color: const Color(0xFFD97706),
        message: 'MQTT conectado, aguardando leituras.',
      );
    }

    final stale = DateTime.now().difference(lastMetricTime).inMinutes >= 5;
    if (stale) {
      return _MonitoringStatusVisual(
        icon: Icons.sensors,
        color: const Color(0xFFD97706),
        message: 'Última leitura ${_relativeTime(lastMetricTime)}.',
      );
    }

    return _MonitoringStatusVisual(
      icon: status.backgroundActive ? Icons.sensors : Icons.sensors_outlined,
      color: const Color(0xFF15803D),
      message: status.backgroundActive
          ? 'Monitoramento ativo em segundo plano.'
          : 'MQTT conectado com leitura recente.',
    );
  }

  return _MonitoringStatusVisual(
    icon: Icons.cloud_off,
    color: const Color(0xFF64748B),
    message: status.lastMessage ?? 'MQTT $phaseLabel.',
  );
}

String _phaseLabel(MqttConnectionPhase phase) {
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

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) {
    return 'há instantes';
  }
  if (difference.inHours < 1) {
    return 'há ${difference.inMinutes} min';
  }
  return 'há ${difference.inHours} h';
}

class _MonitoringStatusVisual {
  final IconData icon;
  final Color color;
  final String message;

  const _MonitoringStatusVisual({
    required this.icon,
    required this.color,
    required this.message,
  });
}

class _ForecastCard extends StatelessWidget {
  final ForecastSnapshot snapshot;

  const _ForecastCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDarkMode ? Colors.white70 : const Color(0xFF475569);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Text(
                'Previsao local',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${snapshot.trendLabel} com base em ${snapshot.sampleCount} leituras recentes.',
            style: TextStyle(color: subtitleColor),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _ForecastMetricChip(
                label: 'Potencia em 30 min',
                value: '${formatWithSIPrefix(snapshot.projectedPowerWatts)} W',
              ),
              _ForecastMetricChip(
                label: 'Energia em 1 h',
                value: '${snapshot.projectedEnergyKwh.toStringAsFixed(3)} kWh',
              ),
              _ForecastMetricChip(
                label: 'Inclinacao',
                value: '${snapshot.powerSlopePerMinute.toStringAsFixed(2)} W/min',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForecastMetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _ForecastMetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
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
