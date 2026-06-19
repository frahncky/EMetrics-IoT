import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_settings_provider.dart';
import '../../providers/mqtt_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../providers/dashboard_preferences_provider.dart';
import '../../providers/forecast_provider.dart';
import '../../providers/metric_provider.dart';
import '../../theme/app_colors.dart';
import 'dashboard_tabs.dart';
import '../shared/mqtt_connection_status_icon.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  /// Sincroniza o estado do serviço MQTT em segundo plano com o provider de status.
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
    // Ativa o saver para que métricas MQTT sejam persistidas enquanto a tela estiver visível.
    ref.watch(mqttMetricSaverProvider);
    final mqttSettings = ref.watch(mqttSettingsProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final dashboardPreferences = ref.watch(dashboardPreferencesProvider);
    final forecastAsync = ref.watch(forecastProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [
                      AppColors.darkSurface,
                      AppColors.darkScaffold.withValues(alpha: 0.9),
                    ]
                  : [
                      AppColors.lightCard,
                      AppColors.lightScaffold,
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
              size: 28,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'E-Metrics IoT',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.2,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        centerTitle: false,
        foregroundColor: isDarkMode ? Colors.white : Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const MqttConnectionStatusIcon(rightPadding: 0),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                  ),
                  child: Text(
                    'Dispositivo: ${mqttSettings.profileName}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode
                          ? Colors.white54
                          : AppColors.lightTextSmall,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // Drawer removido
      body: SafeArea(
        child: metricsAsync.when(
          data: (metrics) {
            final last = metrics.isNotEmpty ? metrics.first : null;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
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
                          frequency: last?.frequency ?? 0,
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
                  ),
                ),
                SliverFillRemaining(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: DashboardTabs(),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Erro ao carregar dados: $e',
              style: const TextStyle(color: AppColors.errorDataText),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card de previsão ─────────────────────────────────────────────────────────

/// Card exibido no dashboard com previsão de potência e energia baseada em regressão linear
/// das últimas leituras. Só aparece quando habilitado nas preferências de dashboard.
class _ForecastCard extends StatelessWidget {
  final ForecastSnapshot snapshot;

  const _ForecastCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDarkMode ? Colors.white : AppColors.lightTextTitle;
    final subtitleColor = isDarkMode ? Colors.white70 : AppColors.lightTextSmall;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [
                  Theme.of(context).cardColor,
                  AppColors.darkSurface.withValues(alpha: 0.9),
                ]
              : [
                  AppColors.lightCard,
                  AppColors.lightScaffold,
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.forecastBorder.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: AppColors.forecastBorder),
              const SizedBox(width: 8),
              Text(
                'Previsão local',
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
                label: 'Potência em 30 min',
                value: '${formatWithSIPrefix(snapshot.projectedPowerWatts)} W',
              ),
              _ForecastMetricChip(
                label: 'Energia em 1 h',
                value: '${snapshot.projectedEnergyKwh.toStringAsFixed(3)} kWh',
              ),
              _ForecastMetricChip(
                label: 'Inclinação',
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
        color: isDarkMode ? AppColors.forecastChipDark : AppColors.lightScaffold,
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

// ── Indicadores de métricas ──────────────────────────────────────────────────

/// Grade de 8 cards com as grandezas elétricas calculadas e medidas pelo PZEM004T.
class _MainIndicators extends StatelessWidget {
  final double voltage;
  final double current;
  final double power;
  final double frequency;
  final double energy;
  final double pf;
  const _MainIndicators({
    this.voltage = 0,
    this.current = 0,
    this.power = 0,
    this.frequency = 0,
    this.energy = 0,
    this.pf = 0,
  });

  @override
  Widget build(BuildContext context) {
    final double apparent = voltage * current;
    final double active = power;
    final double reactive = math.sqrt(
      math.max((apparent * apparent) - (active * active), 0),
    );
    const spacing = 8.0;
    // Cada card representa uma grandeza elétrica medida pelo PZEM004T.
    final cards = [
      _IndicatorCard(
        label: 'Aparente',
        value: formatWithSIPrefix(apparent),
        icon: Icons.data_usage,
        color: AppColors.metricApparent,
        compact: true,
        unit: 'VA',
      ),
      _IndicatorCard(
        label: 'Ativa',
        value: formatWithSIPrefix(power),
        icon: Icons.flash_on_outlined,
        color: AppColors.metricActive,
        compact: true,
        unit: 'W',
      ),
      _IndicatorCard(
        label: 'Reativa',
        value: formatWithSIPrefix(reactive),
        icon: Icons.waves,
        color: AppColors.metricReactive,
        compact: true,
        unit: 'VAr',
      ),
      _IndicatorCard(
        label: 'FP',
        value: pf.isNaN ? '--' : pf.toStringAsFixed(2),
        icon: Icons.speed_outlined,
        color: AppColors.metricPf,
        compact: true,
        extraCompact: true,
      ),
      _IndicatorCard(
        label: 'Tensão',
        value: formatWithSIPrefix(voltage, fractionDigits: 1),
        icon: Icons.electrical_services,
        color: AppColors.metricVoltage,
        compact: true,
        unit: 'V',
      ),
      _IndicatorCard(
        label: 'Corrente',
        value: formatWithSIPrefix(current),
        icon: Icons.bolt_outlined,
        color: AppColors.metricCurrent,
        compact: true,
        unit: 'A',
      ),
      _IndicatorCard(
        label: 'Energia',
        value: formatWithSIPrefix(energy, fractionDigits: 3),
        icon: Icons.battery_charging_full_outlined,
        color: AppColors.metricEnergy,
        compact: true,
        unit: 'kWh',
      ),
      _IndicatorCard(
        label: 'Frequência',
        value: frequency > 0 ? frequency.toStringAsFixed(2) : '--',
        icon: Icons.ssid_chart,
        color: AppColors.metricFrequency,
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

// ── Card individual de métrica ────────────────────────────────────────────────

/// Card compacto exibindo uma grandeza elétrica com ícone, valor e unidade.
///
/// O parâmetro [compact] reduz o tamanho para caber em grades de 4 colunas.
/// O parâmetro [extraCompact] reduz ainda mais para grandezas adimensionais (FP, Hz).
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
    final textColor = isDarkMode ? Colors.white : AppColors.lightTextBody;
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: isDarkMode ? 0.14 : 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
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
                                  : AppColors.lightUnselected,
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
