import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import '../../data/metric_model.dart';
import 'history_export_writer_stub.dart'
    if (dart.library.io) 'history_export_writer_io.dart'
    if (dart.library.html) 'history_export_writer_web.dart';

class HistoryExportButton extends StatelessWidget {
  final List<Metric> metrics;
  const HistoryExportButton({super.key, required this.metrics});

  Future<void> _exportCSV(BuildContext context) async {
    final rows = [
      [
        'Data/Hora',
        'Tensão (V)',
        'Corrente (A)',
        'Potência (W)',
        'FP',
        'Frequência (Hz)',
        'Energia (kWh)',
      ],
      ...metrics.map(
        (m) => [
          m.timestamp.toIso8601String(),
          m.voltage,
          m.current,
          m.power,
          m.pf,
          m.frequency,
          m.energy,
        ],
      ),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final result = await writeHistoryCsv(csv, 'historico_emetrics.csv');
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
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
