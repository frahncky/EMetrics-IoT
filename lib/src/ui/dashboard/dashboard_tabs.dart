import 'package:flutter/material.dart';
import 'realtime_chart.dart';


class DashboardTabs extends StatefulWidget {
  const DashboardTabs({super.key});

  @override
  State<DashboardTabs> createState() => _DashboardTabsState();
}

class _DashboardTabsState extends State<DashboardTabs> {
  String _selectedField1 = 'power';
  String _selectedField2 = 'energy';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Expanded(
          child: _ChartWithSelector(
            selectedField: _selectedField1,
            onChanged: (f) => setState(() => _selectedField1 = f),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _ChartWithSelector(
            selectedField: _selectedField2,
            onChanged: (f) => setState(() => _selectedField2 = f),
          ),
        ),
      ],
    );
  }
}

class _ChartWithSelector extends StatelessWidget {
  final String selectedField;
  final ValueChanged<String> onChanged;
  const _ChartWithSelector({required this.selectedField, required this.onChanged});

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
  const _RealtimeChartWithInternalSelector({required this.selectedField, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const fields = [
      {'label': 'Tensão', 'value': 'voltage'},
      {'label': 'Corrente', 'value': 'current'},
      {'label': 'Potência', 'value': 'power'},
      {'label': 'Fator Potência', 'value': 'pf'},
      {'label': 'Frequência', 'value': 'frequency'},
      {'label': 'Energia', 'value': 'energy'},
    ];
    final secondaryColor = Theme.of(context).colorScheme.secondary;
    final backgroundColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1F2937);
    
    return RealtimeChart(
      field: selectedField,
      fieldSelector: (context) {
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedField,
            dropdownColor: backgroundColor,
            style: TextStyle(color: secondaryColor, fontWeight: FontWeight.bold, fontSize: 16),
            icon: Icon(Icons.arrow_drop_down, color: secondaryColor),
            onChanged: (v) => v != null ? onChanged(v) : null,
            items: fields.map((f) => DropdownMenuItem(
              value: f['value'],
              child: Text(f['label']!, style: TextStyle(color: textColor)),
            )).toList(),
          ),
        );
      },
    );
  }
}
