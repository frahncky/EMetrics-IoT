import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER,
            voltage REAL,
            current REAL,
            power REAL,
            pf REAL,
            frequency REAL,
            energy REAL
          )
        ''');
        await _createUniqueMetricIndex(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createUniqueMetricIndex(db);
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
}
