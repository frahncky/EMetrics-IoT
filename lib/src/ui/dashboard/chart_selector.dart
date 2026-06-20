import 'package:flutter/material.dart';

class ChartSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const ChartSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const fields = [
      {'label': 'Potência (W)', 'value': 'power'},
      {'label': 'Energia Ativa (kWh)', 'value': 'energy_active'},
      {'label': 'Energia Aparente (kVAh)', 'value': 'energy_apparent'},
      {'label': 'Energia Reativa (kVArh)', 'value': 'energy_reactive'},
      {'label': 'Fator de potência', 'value': 'pf'},
    ];
    return Wrap(
      spacing: 8,
      children: fields
          .map(
            (f) => ChoiceChip(
              label: Text(f['label']!),
              selected: selected == f['value'],
              onSelected: (_) => onChanged(f['value']!),
            ),
          )
          .toList(),
    );
  }
}
