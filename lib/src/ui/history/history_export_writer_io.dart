import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> writeHistoryCsv(String csv, String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csv);
  return 'Exportado para ${file.path}';
}
