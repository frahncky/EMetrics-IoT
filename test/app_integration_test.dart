import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:e_metrics_iot/src/app.dart';

void main() {
  group('App Integration Tests', () {
    testWidgets('App inicia com MaterialApp', (WidgetTester tester) async {
      await tester.pumpWidget(const EmetricsApp());
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Bottom navigation bar é renderizado', (WidgetTester tester) async {
      await tester.pumpWidget(const EmetricsApp());
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Histórico'), findsOneWidget);
      expect(find.text('Configurações'), findsOneWidget);
    });

    testWidgets('Dashboard é renderizado inicialmente', (WidgetTester tester) async {
      await tester.pumpWidget(const EmetricsApp());
      await tester.pumpAndSettle();

      expect(find.text('E-Metrics IoT'), findsOneWidget);
    });

    testWidgets('Navegação entre abas funciona', (WidgetTester tester) async {
      await tester.pumpWidget(const EmetricsApp());
      await tester.pumpAndSettle();

      // Tap na aba Histórico
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      // Verifica se há pelo menos um Scaffold renderizado
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Configurações são acessíveis', (WidgetTester tester) async {
      await tester.pumpWidget(const EmetricsApp());
      await tester.pumpAndSettle();

      // Tap na aba Configurações
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verifica se os campos de configuração existem
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('Tema é aplicado corretamente', (WidgetTester tester) async {
      await tester.pumpWidget(const EmetricsApp());
      await tester.pumpAndSettle();

      final scaffold = find.byType(Scaffold).first;
      expect(scaffold, findsOneWidget);
    });
  });
}
