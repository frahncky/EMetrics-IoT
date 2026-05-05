// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:e_metrics_iot/src/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App inicia sem faixa debug e exibe navegação principal', (WidgetTester tester) async {
    await tester.pumpWidget(const EmetricsApp());
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Alertas'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
  });
}
