import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/dashboard/dashboard_page.dart';

class EmetricsApp extends StatelessWidget {
  const EmetricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'E-Metrics IoT',
        theme: ThemeData.dark(),
        home: const DashboardPage(),
      ),
    );
  }
}
