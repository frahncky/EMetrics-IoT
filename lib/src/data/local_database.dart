import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton de acesso ao banco SQLite local (`emetrics.db`).
///
/// Histórico de migrações:
/// - v1 → v2: criou índice único em `metrics` para evitar leituras duplicadas.
/// - v2 → v3: adicionou tabela `integration_sync_queue` para fila de exportação.
/// - v3 → v4: adicionou colunas `temperature` (E3) e `crc_errors` (E8) em `metrics`.
/// - v4 → v5: adicionou `received_at` para diferenciar hora de medição e chegada.
class LocalDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'emetrics.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER,
            received_at INTEGER,
            voltage REAL,
            current REAL,
            power REAL,
            pf REAL,
            frequency REAL,
            energy REAL,
            temperature REAL,
            crc_errors INTEGER
          )
        ''');
        await _createUniqueMetricIndex(db);
        await _createIntegrationSyncQueueTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createUniqueMetricIndex(db);
        }
        if (oldVersion < 3) {
          await _createIntegrationSyncQueueTable(db);
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE metrics ADD COLUMN temperature REAL');
          await db.execute('ALTER TABLE metrics ADD COLUMN crc_errors INTEGER');
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE metrics ADD COLUMN received_at INTEGER',
          );
        }
      },
    );
  }

  static Future<void> _createUniqueMetricIndex(Database db) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_metrics_unique
      ON metrics(timestamp, voltage, current, power, pf, frequency, energy)
    ''');
  }

  static Future<void> _createIntegrationSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS integration_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        metric_timestamp INTEGER NOT NULL,
        payload TEXT NOT NULL,
        profile_id TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_sync_metric
      ON integration_sync_queue(metric_timestamp, payload)
    ''');
  }
}
