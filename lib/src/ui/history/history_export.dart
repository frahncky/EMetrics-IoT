import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../data/metric_model.dart';

class HistoryExportButton extends StatelessWidget {
  final List<Metric> metrics;
  const HistoryExportButton({super.key, required this.metrics});

  Future<void> _exportCSV(BuildContext context) async {
    final rows = [
      ['Data/Hora', 'Tensão (V)', 'Corrente (A)', 'Potência (W)', 'FP', 'Frequência (Hz)', 'Energia (kWh)'],
      ...metrics.map((m) => [
        m.timestamp.toIso8601String(),
        m.voltage,
        m.current,
        m.power,
        m.pf,
        m.frequency,
        m.energy,
      ])
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/historico_emetrics.csv');
    await file.writeAsString(csv);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exportado para ${file.path}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.download),
      label: const Text('Exportar CSV'),
      onPressed: metrics.isEmpty ? null : () => _exportCSV(context),
    );
  }
}
