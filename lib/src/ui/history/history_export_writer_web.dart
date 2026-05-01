import 'dart:convert';

import 'package:web/web.dart' as web;

Future<String> writeHistoryCsv(String csv, String fileName) async {
  final uri = Uri.dataFromString(csv, mimeType: 'text/csv', encoding: utf8);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = uri.toString();
  anchor.download = fileName;
  anchor.style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return 'Download iniciado: $fileName';
}
