import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardPreferences {
  final String topField;
  final String bottomField;
  final bool showForecastCard;

  const DashboardPreferences({
    required this.topField,
    required this.bottomField,
    required this.showForecastCard,
  });

  DashboardPreferences copyWith({
    String? topField,
    String? bottomField,
    bool? showForecastCard,
  }) {
    return DashboardPreferences(
      topField: topField ?? this.topField,
      bottomField: bottomField ?? this.bottomField,
      showForecastCard: showForecastCard ?? this.showForecastCard,
    );
  }
}

class DashboardPreferencesNotifier extends StateNotifier<DashboardPreferences> {
  static const _topFieldKey = 'dashboard_top_field';
  static const _bottomFieldKey = 'dashboard_bottom_field';
  static const _showForecastKey = 'dashboard_show_forecast';

  DashboardPreferencesNotifier()
      : super(
          const DashboardPreferences(
            topField: 'power',
            bottomField: 'energy',
            showForecastCard: true,
          ),
        ) {
    load();
  }

  Future<DashboardPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final nextState = state.copyWith(
      topField: prefs.getString(_topFieldKey) ?? state.topField,
      bottomField: prefs.getString(_bottomFieldKey) ?? state.bottomField,
      showForecastCard: prefs.getBool(_showForecastKey) ?? state.showForecastCard,
    );
    if (mounted) {
      state = nextState;
    }
    return nextState;
  }

  Future<void> updateTopField(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_topFieldKey, value);
    state = state.copyWith(topField: value);
  }

  Future<void> updateBottomField(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bottomFieldKey, value);
    state = state.copyWith(bottomField: value);
  }

  Future<void> setShowForecastCard(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showForecastKey, value);
    state = state.copyWith(showForecastCard: value);
  }
}

final dashboardPreferencesProvider = StateNotifierProvider<
    DashboardPreferencesNotifier,
    DashboardPreferences>((ref) => DashboardPreferencesNotifier());