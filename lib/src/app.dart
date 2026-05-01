import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/dashboard/dashboard_page.dart';
import 'ui/history/history_page.dart';
import 'ui/settings/settings_page.dart';
import '../src/services/alert_service.dart';
import '../src/providers/alert_provider.dart';
import '../src/providers/theme_provider.dart';

class EmetricsApp extends StatelessWidget {
  const EmetricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _AppInitializer(),
    );
  }
}

class _AppInitializer extends ConsumerWidget {
  const _AppInitializer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AlertService.init();
    ref.read(alertProvider);
    final isDarkMode = ref.watch(themeProvider);
    
    return MaterialApp(
      title: 'E-Metrics IoT',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const _MainMenu(),
    );
  }

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F1419),
      primaryColor: const Color(0xFF00D8FF),
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF00D8FF),
        secondary: const Color(0xFFFFB300),
        surface: const Color(0xFF1A202C),
        tertiary: const Color(0xFF00FF88),
        outline: const Color(0xFF2D3748),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A202C),
        centerTitle: true,
        elevation: 4,
        shadowColor: Color(0x4D000000),
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A202C),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: const BorderSide(color: Color(0xFF2D3748), width: 1),
        ),
        elevation: 4,
        shadowColor: const Color(0x4D000000),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00D8FF),
          foregroundColor: Colors.black87,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF00D8FF),
          side: const BorderSide(color: Color(0xFF00D8FF), width: 2),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF00D8FF),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF0F1419),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF2D3748), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF2D3748), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF00D8FF), width: 2),
        ),
        labelStyle: TextStyle(color: Color(0xFFCBD5E0), fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: Color(0xFF718096)),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, color: Color(0xFFCBD5E0)),
        bodySmall: TextStyle(fontSize: 14, color: Color(0xFFA0AEC0)),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0)),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF7FAFC)),
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFFAFBFC),
      primaryColor: const Color(0xFF4A7BA7),
      colorScheme: ColorScheme.light(
        primary: const Color(0xFF4A7BA7),
        secondary: const Color(0xFF6BA3C5),
        surface: const Color(0xFFFFFEFD),
        tertiary: const Color(0xFF4CAF7F),
        outline: const Color(0xFFE8EAED),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFEFD),
        centerTitle: true,
        elevation: 2,
        shadowColor: Color(0x08000000),
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFEFD),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: const BorderSide(color: Color(0xFFE8EAED), width: 1),
        ),
        elevation: 1,
        shadowColor: const Color(0x05000000),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A7BA7),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 1,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4A7BA7),
          side: const BorderSide(color: Color(0xFF4A7BA7), width: 2),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF4A7BA7),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFBFC),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: const BorderSide(color: Color(0xFFE0E4EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: const BorderSide(color: Color(0xFF4A7BA7), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF52617A), fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: Color(0xFFAEB0B8)),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, color: Color(0xFF3D4A5C)),
        bodySmall: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)),
      ),
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;
    final unselectedColor = isDarkMode ? Colors.white60 : const Color(0xFF9CA3AF);
    
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            backgroundColor: cardColor,
            selectedItemColor: primaryColor,
            unselectedItemColor: unselectedColor,
            items: [
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.home,
                  selected: _selectedIndex == 0,
                  primaryColor: primaryColor,
                ),
                label: 'Início',
              ),
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.history,
                  selected: _selectedIndex == 1,
                  primaryColor: primaryColor,
                ),
                label: 'Histórico',
              ),
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.settings,
                  selected: _selectedIndex == 2,
                  primaryColor: primaryColor,
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
  final Color primaryColor;
  const _NavBarIcon({required this.icon, required this.selected, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor = isDarkMode ? Colors.white60 : const Color(0xFF9CA3AF);
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(4),
      decoration: selected
          ? BoxDecoration(
              color: primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Icon(
        icon,
        color: selected ? primaryColor : unselectedColor,
        size: 28,
      ),
    );
  }
}
