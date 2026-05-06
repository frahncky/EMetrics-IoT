import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'ui/alerts/alerts_page.dart';
import 'ui/dashboard/dashboard_page.dart';
import 'ui/history/history_page.dart';
import 'ui/settings/settings_page.dart';
import '../src/providers/alert_provider.dart';
import '../src/providers/device_storage_provider.dart';
import '../src/providers/theme_provider.dart';
import '../src/providers/mqtt_metric_saver.dart';
import 'theme/app_colors.dart';

class EmetricsApp extends StatelessWidget {
  const EmetricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: _AppInitializer());
  }
}

class _AppInitializer extends ConsumerWidget {
  const _AppInitializer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ativa os providers de efeito colateral (alertas e sincronização automática)
    // via ref.listen sem bloquear o ciclo de renderização.
    ref.listen(alertProvider, (previous, next) {});
    ref.listen(deviceStorageTrackerProvider, (previous, next) {});
    ref.listen(integrationAutoSyncProvider, (previous, next) {});
    final isDarkMode = ref.watch(themeProvider);

    // Escolhe tema com base na preferência salva pelo usuário.
    return MaterialApp(
      title: 'E-Metrics IoT',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const _MainMenu(),
    );
  }

  // ── Tema Escuro ────────────────────────────────────────────────────────
  static ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkScaffold,
      primaryColor: AppColors.darkPrimary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        secondary: AppColors.darkSecondary,
        surface: AppColors.darkSurface,
        tertiary: AppColors.darkTertiary,
        outline: AppColors.darkOutline,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        centerTitle: true,
        elevation: 4,
        shadowColor: AppColors.shadowDark,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.darkTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.darkOutline, width: 1),
        ),
        elevation: 4,
        shadowColor: AppColors.shadowDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: Colors.black87,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          side: const BorderSide(color: AppColors.darkPrimary, width: 2),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkScaffold,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.darkOutline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.darkOutline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.darkPrimary, width: 2),
        ),
        labelStyle: TextStyle(
          color: AppColors.darkTextSecondary,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(color: AppColors.darkHint),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, color: AppColors.darkTextSecondary),
        bodySmall: TextStyle(fontSize: 14, color: AppColors.darkTextTertiary),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.darkTextPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.darkTextTitle,
        ),
      ),
    );
  }

  // ── Tema Claro ─────────────────────────────────────────────────────────
  static ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightScaffold,
      primaryColor: AppColors.lightPrimary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        secondary: AppColors.lightSecondary,
        surface: AppColors.lightSurface,
        tertiary: AppColors.lightTertiary,
        outline: AppColors.lightOutline,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextBody,
        onTertiary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        centerTitle: true,
        elevation: 2,
        shadowColor: AppColors.shadowLight,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.lightTextTitle,
        ),
        iconTheme: IconThemeData(color: AppColors.lightTextBody),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.lightInputBorder, width: 1),
        ),
        elevation: 1,
        shadowColor: AppColors.shadowLight,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lightPrimary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 1,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          side: const BorderSide(color: AppColors.lightPrimary, width: 1.5),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightInputFill,
        floatingLabelStyle: TextStyle(
          color: AppColors.lightTextBody,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.lightOutline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.lightInputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.lightPrimary, width: 2),
        ),
        labelStyle: TextStyle(
          color: AppColors.lightLabel,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(color: AppColors.lightHint),
      ),
      dividerColor: AppColors.lightInputBorder,
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.lightTextBody,
        iconColor: AppColors.lightTextBody,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, color: AppColors.lightTextBody),
        bodySmall: TextStyle(fontSize: 14, color: AppColors.lightTextSmall),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.lightTextTitle,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.lightTextBody,
        ),
      ),
    );
  }
}

class _MainMenu extends StatefulWidget {
  const _MainMenu();

  @override
  State<_MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<_MainMenu> {
  int _selectedIndex = 0;
  static final List<Widget> _pages = <Widget>[
    DashboardPage(),
    HistoryPage(),
    AlertsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;
    // Cor de itens não selecionados difere entre temas para manter contraste.
    final unselectedColor = isDarkMode
        ? Colors.white60
        : AppColors.lightUnselected;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.3, 0.0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _pages[_selectedIndex],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
                  icon: Icons.notifications_outlined,
                  selected: _selectedIndex == 2,
                  primaryColor: primaryColor,
                ),
                label: 'Alertas',
              ),
              BottomNavigationBarItem(
                icon: _NavBarIcon(
                  icon: Icons.settings,
                  selected: _selectedIndex == 3,
                  primaryColor: primaryColor,
                ),
                label: 'Configurações',
              ),
            ],
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 13,
            unselectedFontSize: 12,
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
  const _NavBarIcon({
    required this.icon,
    required this.selected,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor = isDarkMode
        ? Colors.white60
        : AppColors.lightUnselected;

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
