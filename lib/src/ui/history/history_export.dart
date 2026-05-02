import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/metric_model.dart';
import 'history_export_writer_stub.dart'
    if (dart.library.io) 'history_export_writer_io.dart'
    if (dart.library.html) 'history_export_writer_web.dart';

Future<Uint8List> buildHistoryPdfBytes(List<Metric> metrics) async {
  final pdf = pw.Document();
  final sortedMetrics = [...metrics]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  String formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  final rows = [
    <String>['Data/Hora', 'Tensao', 'Corrente', 'Potencia', 'FP', 'Frequencia', 'Energia'],
    ...sortedMetrics.map(
      (m) => [
        formatDate(m.timestamp),
        m.voltage.toStringAsFixed(2),
        m.current.toStringAsFixed(2),
        m.power.toStringAsFixed(2),
        m.pf.toStringAsFixed(2),
        m.frequency.toStringAsFixed(2),
        m.energy.toStringAsFixed(3),
      ],
    ),
  ];

  final totalConsumption = sortedMetrics.isEmpty
      ? 0.0
      : (sortedMetrics.last.energy - sortedMetrics.first.energy).clamp(0, double.infinity);
  final averagePower = sortedMetrics.isEmpty
      ? 0.0
      : sortedMetrics.map((metric) => metric.power).reduce((a, b) => a + b) /
          sortedMetrics.length;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'Relatorio de medicoes de energia',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Leituras: ${sortedMetrics.length}'),
        if (sortedMetrics.isNotEmpty)
          pw.Text(
            'Período: ${formatDate(sortedMetrics.first.timestamp)} até ${formatDate(sortedMetrics.last.timestamp)}',
          ),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _pdfSummaryCard('Consumo', '${totalConsumption.toStringAsFixed(3)} kWh'),
            _pdfSummaryCard('Potencia media', '${averagePower.toStringAsFixed(1)} W'),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: rows.first,
          data: rows.skip(1).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
          cellAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          cellStyle: const pw.TextStyle(fontSize: 9),
          rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        ),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _pdfSummaryCard(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.blueGrey300),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

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

  Future<void> _exportPdf(BuildContext context) async {
    final bytes = await buildHistoryPdfBytes(metrics);
    if (!context.mounted) {
      return;
    }
    await Printing.layoutPdf(
      name: 'historico_emetrics.pdf',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> _showExportOptions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Exportar CSV'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _exportCSV(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Gerar PDF'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _exportPdf(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.download_outlined),
      label: const Text('Exportar'),
      onPressed: metrics.isEmpty ? null : () => _showExportOptions(context),
    );
  }
}
