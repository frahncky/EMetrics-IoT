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
      {'label': 'Potência (W)', 'value': 'power'},
      {'label': 'Energia (kWh)', 'value': 'energy'},
      {'label': 'Fator Potência', 'value': 'pf'},
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: RealtimeChart(
        field: selectedField,
        fieldSelector: (context) {
          final current = fields.firstWhere((f) => f['value'] == selectedField);
          return DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedField,
              dropdownColor: const Color(0xFF232A34),
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.amber),
              onChanged: (v) => v != null ? onChanged(v) : null,
              items: fields.map((f) => DropdownMenuItem(
                value: f['value'],
                child: Text(f['label']!, style: TextStyle(color: Colors.white)),
              )).toList(),
            ),
          );
        },
      ),
    );
  }
}
