import 'dart:convert';

import 'local_database.dart';
import 'integration_sync_item.dart';
import 'metric_model.dart';
import 'package:sqflite/sqflite.dart';

class MetricRepository {
  Future<void> insertMetric(Metric metric) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'metrics',
      metric.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Metric>> getMetrics({int? from, int? to}) async {
    final db = await LocalDatabase.database;
    final where = <String>[];
    final args = <dynamic>[];
    if (from != null) {
      where.add('timestamp >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('timestamp <= ?');
      args.add(to);
    }
    final result = await db.query(
      'metrics',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'timestamp DESC',
    );
    return result.map((e) => Metric.fromMap(e)).toList();
  }

  Future<void> enqueueMetricSync(Metric metric, {String? profileId}) async {
    final db = await LocalDatabase.database;
    await db.insert('integration_sync_queue', {
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'metric_timestamp': metric.timestamp.millisecondsSinceEpoch,
      'payload': jsonEncode(metric.toMap()),
      'profile_id': profileId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<IntegrationSyncItem>> getPendingMetricSyncItems({
    int limit = 50,
  }) async {
    final db = await LocalDatabase.database;
    final result = await db.query(
      'integration_sync_queue',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return result.map(IntegrationSyncItem.fromMap).toList();
  }

  Future<void> markMetricSyncSucceeded(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final db = await LocalDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.delete(
      'integration_sync_queue',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> markMetricSyncFailed(int id, String error) async {
    final db = await LocalDatabase.database;
    await db.rawUpdate(
      'UPDATE integration_sync_queue '
      'SET attempts = attempts + 1, last_error = ? '
      'WHERE id = ?',
      [error, id],
    );
  }
}
