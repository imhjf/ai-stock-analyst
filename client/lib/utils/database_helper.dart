import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('stocks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const nullableTextType = 'TEXT';
    const intType = 'INTEGER';

    await db.execute('''
CREATE TABLE IF NOT EXISTS stocks (
  id $idType,
  name $textType,
  code $textType,
  status $intType, 
  sd $nullableTextType,
  message $nullableTextType,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  analyst_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < newVersion) {
      // 检查 filepath 字段是否存在
      final tableInfo = await db.rawQuery("PRAGMA table_info(stocks)");
      final hasFilepath = tableInfo.any(
        (column) => column['name'] == 'filepath',
      );

      if (hasFilepath) {
        // 创建临时表
        await db.execute('''
CREATE TABLE stocks_temp (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  status INTEGER,
  sd TEXT,
  message TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  analyst_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)''');

        // 复制数据到临时表（不包含 filepath 字段）
        await db.execute('''
INSERT INTO stocks_temp (id, name, code, status, sd, message, created_at, analyst_at)
SELECT id, name, code, status, sd, message, created_at, analyst_at FROM stocks
''');

        // 删除原表
        await db.execute('DROP TABLE stocks');

        // 重命名临时表
        await db.execute('ALTER TABLE stocks_temp RENAME TO stocks');
      }
    }
  }

  Future<int> insertStock(String name, String code) async {
    final db = await database;

    try {
      final n = DateTime.now().toIso8601String();
      final data = {
        'name': name,
        'code': code,
        'status': 0,
        'created_at': n,
        'analyst_at': n,
      };

      return await db.insert('stocks', data);
    } catch (e) {
      print('Error inserting stock: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getStocks() async {
    try {
      final db = await database;
      return await db.query('stocks', orderBy: 'created_at DESC');
    } catch (e) {
      print('Error getting stocks: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getStock(int id) async {
    try {
      final db = await database;
      List result = await db.query('stocks', where: 'id = ?', whereArgs: [id]);
      return result[0];
    } catch (e) {
      print('Error getting stock: $e');
      return {};
    }
  }

  Future<void> updateStock(int id, Map<String, dynamic> data) async {
    try {
      final db = await database;
      final result = await db.update(
        'stocks',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (result == 0) {
        print('Warning: No stock found with id $id to update status');
      }
    } catch (e) {
      print('Error getting stock: $e');
    }
  }

  Future<void> deleteStockByIds(List<int> ids) async {
    try {
      final db = await database;
      final placeholders = List.generate(ids.length, (index) => '?').join(',');
      await db.delete('stocks', where: 'id IN ($placeholders)', whereArgs: ids);
    } catch (e) {
      print('Error deleting stock: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getStocksByIds(List<int> ids) async {
    final db = await database;
    // 将ids列表转换为字符串列表，并用逗号连接
    final placeholders = List.generate(ids.length, (index) => '?').join(',');
    List<Map<String, dynamic>> result = await db.query(
      'stocks',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return result;
  }
}
