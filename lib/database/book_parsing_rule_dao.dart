import 'package:sqflite/sqflite.dart';
import '../models/book_parsing_rule.dart';
import 'database_helper.dart';

class BookParsingRuleDao {
  Future<Database> get _db async => DatabaseHelper.instance.database;

  Future<BookParsingRule?> getByItemId(int itemId) async {
    final db = await _db;
    final maps = await db.query(
      'book_parsing_rules',
      where: 'itemId = ?',
      whereArgs: [itemId],
    );
    if (maps.isEmpty) return null;
    return BookParsingRule.fromMap(maps.first);
  }

  Future<void> save(BookParsingRule rule) async {
    final db = await _db;
    await db.insert(
      'book_parsing_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(int itemId) async {
    final db = await _db;
    await db.delete(
      'book_parsing_rules',
      where: 'itemId = ?',
      whereArgs: [itemId],
    );
  }
}
