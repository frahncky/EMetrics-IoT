import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AlertSeverity { warning, critical, info }

class AlertRecord {
  final String id;
  final String title;
  final String message;
  final String type;
  final AlertSeverity severity;
  final DateTime createdAt;
  final bool acknowledged;

  const AlertRecord({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.severity,
    required this.createdAt,
    this.acknowledged = false,
  });

  AlertRecord copyWith({bool? acknowledged}) {
    return AlertRecord(
      id: id,
      title: title,
      message: message,
      type: type,
      severity: severity,
      createdAt: createdAt,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'message': message,
    'type': type,
    'severity': severity.name,
    'createdAt': createdAt.toIso8601String(),
    'acknowledged': acknowledged,
  };

  factory AlertRecord.fromMap(Map<String, dynamic> map) {
    return AlertRecord(
      id: map['id'] as String,
      title: map['title'] as String,
      message: map['message'] as String,
      type: map['type'] as String,
      severity: AlertSeverity.values.byName(map['severity'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      acknowledged: map['acknowledged'] as bool? ?? false,
    );
  }
}

class AlertHistoryNotifier extends StateNotifier<List<AlertRecord>> {
  static const _prefsKey = 'alert_history_records';

  AlertHistoryNotifier() : super(const []) {
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      state = const [];
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    state = decoded
        .cast<Map<String, dynamic>>()
        .map(AlertRecord.fromMap)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> add(AlertRecord record) async {
    state = [record, ...state].take(100).toList();
    await _persist();
  }

  Future<void> acknowledge(String id) async {
    state = [
      for (final record in state)
        if (record.id == id) record.copyWith(acknowledged: true) else record,
    ];
    await _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(state.map((record) => record.toMap()).toList()),
    );
  }
}

final alertHistoryProvider =
    StateNotifierProvider<AlertHistoryNotifier, List<AlertRecord>>(
      (ref) => AlertHistoryNotifier(),
    );