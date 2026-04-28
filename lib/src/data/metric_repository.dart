import 'local_database.dart';
import 'metric_model.dart';

class MetricRepository {
  Future<void> insertMetric(Metric metric) async {
    final db = await LocalDatabase.database;
    await db.insert('metrics', metric.toMap());
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
}
