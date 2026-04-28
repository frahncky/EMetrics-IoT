import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/dashboard/dashboard_page.dart';
import '../src/services/alert_service.dart';
import '../src/providers/alert_provider.dart';

class EmetricsApp extends StatelessWidget {
  const EmetricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _AppInitializer(),
    );
  }
}

class _AppInitializer extends StatefulWidget {
  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  @override
  void initState() {
    super.initState();
    AlertService.init();
  }

  @override
  Widget build(BuildContext context) {
    // Ativa o provider de alertas
    ProviderScope.containerOf(context, listen: false).read(alertProvider);
    return MaterialApp(
      title: 'E-Metrics IoT',
      theme: ThemeData(
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 18),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const DashboardPage(),
    );
  }
}
