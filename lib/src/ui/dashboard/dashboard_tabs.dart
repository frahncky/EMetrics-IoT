import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/dashboard_preferences_provider.dart';
import 'realtime_chart.dart';

class DashboardTabs extends ConsumerWidget {
  const DashboardTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(dashboardPreferencesProvider);
    return Column(
      children: [
        const SizedBox(height: 6),
        Expanded(
          child: _ChartWithSelector(
            selectedField: preferences.topField,
            onChanged: (field) async {
              await ref
                  .read(dashboardPreferencesProvider.notifier)
                  .updateTopField(field);
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _ChartWithSelector(
            selectedField: preferences.bottomField,
            onChanged: (field) async {
              await ref
                  .read(dashboardPreferencesProvider.notifier)
                  .updateBottomField(field);
            },
          ),
        ),
      ],
    );
  }
}

class _ChartWithSelector extends StatelessWidget {
  final String selectedField;
  final ValueChanged<String> onChanged;
  const _ChartWithSelector({
    required this.selectedField,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _RealtimeChartWithInternalSelector(
      selectedField: selectedField,
      onChanged: onChanged,
    );
  }
}

class _RealtimeChartWithInternalSelector extends StatelessWidget {
  final String selectedField;
  final ValueChanged<String> onChanged;
  const _RealtimeChartWithInternalSelector({
    required this.selectedField,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const fields = [
      {'label': 'Tensão', 'value': 'voltage'},
      {'label': 'Corrente', 'value': 'current'},
      {'label': 'Potência Ativa', 'value': 'power'},
      {'label': 'Potência Aparente', 'value': 'power_apparent'},
      {'label': 'Potência Reativa', 'value': 'power_reactive'},
      {'label': 'Fator de potência', 'value': 'pf'},
      {'label': 'Frequência', 'value': 'frequency'},
      {'label': 'Energia Ativa', 'value': 'energy_active'},
      {'label': 'Energia Aparente', 'value': 'energy_apparent'},
      {'label': 'Energia Reativa', 'value': 'energy_reactive'},
    ];
    final secondaryColor = Theme.of(context).colorScheme.secondary;
    final backgroundColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF1F2937);

    return RealtimeChart(
      field: selectedField,
      fieldSelector: (context) {
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedField,
            dropdownColor: backgroundColor,
            style: TextStyle(
              color: secondaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            icon: Icon(Icons.arrow_drop_down, color: secondaryColor),
            onChanged: (v) => v != null ? onChanged(v) : null,
            items: fields
                .map(
                  (f) => DropdownMenuItem(
                    value: f['value'],
                    child: Text(
                      f['label']!,
                      style: TextStyle(color: textColor),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
