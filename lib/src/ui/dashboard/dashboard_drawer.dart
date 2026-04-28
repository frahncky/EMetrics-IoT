import 'package:flutter/material.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';
import '../alerts/alerts_page.dart';

class DashboardDrawer extends StatelessWidget {
  const DashboardDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blueGrey),
            child: Text('E-Metrics IoT', style: TextStyle(fontSize: 24, color: Colors.white)),
          ),
          ListTile(
            leading: Icon(Icons.dashboard),
            title: Text('Dashboard'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.history),
            title: Text('Histórico'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
            },
          ),
          ListTile(
            leading: Icon(Icons.notifications),
            title: Text('Alertas'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsPage()));
            },
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text('Configurações'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
        ],
      ),
    );
  }
}
