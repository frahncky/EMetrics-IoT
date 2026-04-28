import 'package:flutter/material.dart';

enum HistoryPeriod { hora, dia, semana, mes }

class HistoryFilter extends StatelessWidget {
  final HistoryPeriod selected;
  final ValueChanged<HistoryPeriod> onChanged;
  const HistoryFilter({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: HistoryPeriod.values.map((period) {
        final label = switch (period) {
          HistoryPeriod.hora => 'Hora',
          HistoryPeriod.dia => 'Dia',
          HistoryPeriod.semana => 'Semana',
          HistoryPeriod.mes => 'Mês',
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(label),
            selected: selected == period,
            onSelected: (_) => onChanged(period),
          ),
        );
      }).toList(),
    );
  }
}
