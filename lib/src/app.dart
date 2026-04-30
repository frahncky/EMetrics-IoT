import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/dashboard/dashboard_page.dart';
import 'ui/history/history_page.dart';
import 'ui/settings/settings_page.dart';
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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF181F2A),
        primaryColor: const Color(0xFF232B3E),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF232B3E),
          secondary: const Color(0xFFFFB300),
          background: const Color(0xFF181F2A),
          surface: const Color(0xFF232B3E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF232B3E),
          centerTitle: true,
          elevation: 2,
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF232B3E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          elevation: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB300),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFFFB300)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFFB300),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF232B3E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFFFB300)),
          ),
          labelStyle: TextStyle(color: Colors.white70),
          hintStyle: TextStyle(color: Colors.white38),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: Colors.white70),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const _MainMenu(),
    );
  }
}

class _MainMenu extends StatefulWidget {
  const _MainMenu({Key? key}) : super(key: key);
  @override
  State<_MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<_MainMenu> {
  int _selectedIndex = 0;
  static final List<Widget> _pages = <Widget>[
    DashboardPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            backgroundColor: const Color(0xFF232B3E),
            selectedItemColor: const Color(0xFFFFB300),
            unselectedItemColor: Colors.white70,
            items: [
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.home,
                  selected: _selectedIndex == 0,
                ),
                label: 'Início',
              ),
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.history,
                  selected: _selectedIndex == 1,
                ),
                label: 'Histórico',
              ),
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.settings,
                  selected: _selectedIndex == 2,
                ),
                label: 'Configurações',
              ),
            ],
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 14,
            unselectedFontSize: 13,
            showUnselectedLabels: true,
            elevation: 8,
          ),
        ),
      ),
    );
  }

}

class _NavBarIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  const _NavBarIcon({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(4),
      decoration: selected
          ? BoxDecoration(
              color: const Color(0xFFFFB300).withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Icon(
        icon,
        color: selected ? const Color(0xFFFFB300) : Colors.white70,
        size: 28,
      ),
    );
  }
}
