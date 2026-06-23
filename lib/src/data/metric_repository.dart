import 'dart:convert';

import 'local_database.dart';
import 'integration_sync_item.dart';
import 'metric_model.dart';
import 'package:sqflite/sqflite.dart';

/// Repositório de acesso ao banco local SQLite para métricas e fila de
/// sincronização com serviços de integração externos.
class MetricRepository {
  /// Insere uma métrica no banco. Ignora duplicatas (mesmo timestamp + valores).
  Future<void> insertMetric(Metric metric) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'metrics',
      metric.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Retorna métricas em ordem decrescente de timestamp (mais recente primeiro).
  ///
  /// Filtra pelo intervalo [from]..[to] em epoch milissegundos quando fornecidos.
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

  /// Remove todas as métricas do banco local.
  Future<void> deleteAllMetrics() async {
    final db = await LocalDatabase.database;
    await db.delete('metrics');
  }

  /// Remove metricas anteriores a [cutoff] do banco local.
  Future<int> deleteMetricsOlderThan(DateTime cutoff) async {
    final db = await LocalDatabase.database;
    return db.delete(
      'metrics',
      where: 'timestamp < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  /// Adiciona uma métrica à fila de sincronização de integração.
  ///
  /// Usa [profileId] para associar o item ao perfil MQTT ativo no momento da ingestão.
  Future<void> enqueueMetricSync(Metric metric, {String? profileId}) async {
    final db = await LocalDatabase.database;
    await db.insert('integration_sync_queue', {
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'metric_timestamp': metric.timestamp.millisecondsSinceEpoch,
      'payload': jsonEncode(metric.toMap()),
      'profile_id': profileId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Retorna até [limit] itens pendentes da fila de sincronização, do mais antigo ao mais recente.
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

  /// Remove os itens da fila cujos [ids] foram sincronizados com sucesso.
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

  /// Incrementa o contador de tentativas e registra o último [error] para o item [id].
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
