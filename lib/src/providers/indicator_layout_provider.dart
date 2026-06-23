import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IndicatorLayoutNotifier extends StateNotifier<List<String>> {
  static const _key = 'indicator_layout_v1';
  static const defaultLayout = <String>[
    'energy_apparent',
    'power',
    'energy_reactive',
    'pf',
    'voltage',
    'current',
    'energy',
    'frequency',
  ];

  IndicatorLayoutNotifier() : super(List<String>.from(defaultLayout)) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored != null && stored.length == defaultLayout.length && mounted) {
      state = stored;
    }
  }

  Future<void> updateSlot(int index, String field) async {
    final next = List<String>.from(state);
    next[index] = field;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next);
  }
}

final indicatorLayoutProvider =
    StateNotifierProvider<IndicatorLayoutNotifier, List<String>>(
      (ref) => IndicatorLayoutNotifier(),
    );
