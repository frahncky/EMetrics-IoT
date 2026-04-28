import 'package:flutter/material.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';
import '../alerts/alerts_page.dart';
import 'compare_metrics_page.dart';

class DashboardDrawer extends StatelessWidget {
  const DashboardDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueGrey, Colors.black87],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: const Text('E-Metrics IoT', style: TextStyle(fontSize: 22)),
            accountEmail: const Text('monitoramento@iot.com'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.amber,
              child: Icon(Icons.electric_bolt, color: Colors.white, size: 36, semanticLabel: 'Ícone do app'),
            ),
          ),
          const Divider(),
          Semantics(
            label: 'Ir para Dashboard',
            button: true,
            child: ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
          ),
          Semantics(
            label: 'Ir para Histórico',
            button: true,
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Histórico'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
              },
            ),
          ),
          Semantics(
            label: 'Ir para Comparativo de Métricas',
            button: true,
            child: ListTile(
              leading: const Icon(Icons.show_chart),
              title: const Text('Comparativo de Métricas'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareMetricsPage()));
              },
            ),
          ),
          Semantics(
            label: 'Ir para Alertas',
            button: true,
            child: ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Alertas'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsPage()));
              },
            ),
          ),
          Semantics(
            label: 'Ir para Configurações',
            button: true,
            child: ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configurações'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
          ),
        ],
      ),
    );
  }
}
