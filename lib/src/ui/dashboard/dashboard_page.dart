import '../../providers/mqtt_metric_saver.dart';
import '../../providers/mqtt_settings_provider.dart';
import '../../providers/mqtt_status_provider.dart';
import '../../data/metric_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
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
                        child: _MainIndicators(metric: last),
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
String formatWithSIPrefix(num value, {int? fractionDigits}) {
  if (value == 0 || value.isNaN) return '--';
  final abs = value.abs();
  int digits(double v) {
    if (v >= 100) return 0;
    if (v >= 10) return 1;
    return 2;
  }

  if (abs >= 1e9) {
    final d = fractionDigits ?? digits(abs / 1e9);
    return '${(value / 1e9).toStringAsFixed(d)} G';
  } else if (abs >= 1e6) {
    final d = fractionDigits ?? digits(abs / 1e6);
    return '${(value / 1e6).toStringAsFixed(d)} M';
  } else if (abs >= 1e3) {
    final d = fractionDigits ?? digits(abs / 1e3);
    return '${(value / 1e3).toStringAsFixed(d)} K';
  } else if (abs < 1e-3 && abs > 0) {
    final d = fractionDigits ?? digits(abs * 1e6);
    return '${(value * 1e6).toStringAsFixed(d)} μ';
  } else if (abs < 1 && abs >= 1e-3) {
    final d = fractionDigits ?? digits(abs * 1e3);
    return '${(value * 1e3).toStringAsFixed(d)} m';
  } else {
    final d = fractionDigits ?? digits(abs.toDouble());
    return value.toStringAsFixed(d);
  }
}

String formatIndicatorValue(
  double? value, {
  required int fractionDigits,
  required bool hasMeasurement,
}) {
  if (!hasMeasurement || value == null || !value.isFinite) return '--';
  return value.toStringAsFixed(fractionDigits);
}

// ── Indicadores de métricas ──────────────────────────────────────────────────

/// Grade de 8 cards com as grandezas elétricas calculadas e medidas pelo PZEM004T.
class _MainIndicators extends StatelessWidget {
  final Metric? metric;

  const _MainIndicators({this.metric});

  @override
  Widget build(BuildContext context) {
    final hasMeasurement = metric != null;
    final voltage = metric?.voltage;
    final current = metric?.current;
    final power = metric?.power;
    final frequency = metric?.frequency;
    final energy = metric?.energy;
    final pf = metric?.pf;
    final apparent = hasMeasurement ? voltage! * current! : null;
    final reactive = hasMeasurement
        ? math.sqrt(math.max((apparent! * apparent) - (power! * power), 0))
        : null;
    const spacing = 8.0;
    // Cada card representa uma grandeza elétrica medida pelo PZEM004T.
    final cards = [
      _IndicatorCard(
        label: 'Aparente',
        value: formatIndicatorValue(
          apparent,
          fractionDigits: 1,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.data_usage,
        color: AppColors.metricApparent,
        compact: true,
        unit: 'VA',
      ),
      _IndicatorCard(
        label: 'Ativa',
        value: formatIndicatorValue(
          power,
          fractionDigits: 1,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.flash_on_outlined,
        color: AppColors.metricActive,
        compact: true,
        unit: 'W',
      ),
      _IndicatorCard(
        label: 'Reativa',
        value: formatIndicatorValue(
          reactive,
          fractionDigits: 1,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.waves,
        color: AppColors.metricReactive,
        compact: true,
        unit: 'VAr',
      ),
      _IndicatorCard(
        label: 'FP',
        value: formatIndicatorValue(
          pf,
          fractionDigits: 2,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.speed_outlined,
        color: AppColors.metricPf,
        compact: true,
        extraCompact: true,
      ),
      _IndicatorCard(
        label: 'Tensão',
        value: formatIndicatorValue(
          voltage,
          fractionDigits: 1,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.electrical_services,
        color: AppColors.metricVoltage,
        compact: true,
        unit: 'V',
      ),
      _IndicatorCard(
        label: 'Corrente',
        value: formatIndicatorValue(
          current,
          fractionDigits: 3,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.bolt_outlined,
        color: AppColors.metricCurrent,
        compact: true,
        unit: 'A',
      ),
      _IndicatorCard(
        label: 'Energia',
        value: formatIndicatorValue(
          energy,
          fractionDigits: 3,
          hasMeasurement: hasMeasurement,
        ),
        icon: Icons.battery_charging_full_outlined,
        color: AppColors.metricEnergy,
        compact: true,
        unit: 'kWh',
      ),
      _IndicatorCard(
        label: 'Frequência',
        value: formatIndicatorValue(
          frequency,
          fractionDigits: 2,
          hasMeasurement: hasMeasurement,
        ),
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
