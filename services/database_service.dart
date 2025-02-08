import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/quote_model.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _db;
  
  // 获取数据库实例
  Database get database {
    if (_db == null) {
      throw Exception('数据库未初始化');
    }
    return _db!;
  }

  static Future<void> init() async {
    if (kIsWeb) {
      // Web平台暂不初始化数据库
      return;
    }

    if (_db != null) return;

    try {
      final path = await getDatabasesPath();
      _db = await openDatabase(
        join(path, 'daily_quotes.db'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE quotes(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, content TEXT)',
          );
        },
        version: 1,
      );
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }

  Future<void> saveUserQuote(String content) async {
    if (kIsWeb) {
      // Web平台使用其他存储方式或暂不支持
      return;
    }
    try {
      final quote = Quote(
        date: DateTime.now().toIso8601String(),
        content: content,
      );
      
      await database.insert('quotes', quote.toMap());
      notifyListeners();
    } catch (e) {
      debugPrint('保存引用错误: $e');
      rethrow;
    }
  }

  Future<List<Quote>> getAllQuotes() async {
    if (kIsWeb) {
      // Web平台返回空列表
      return [];
    }
    try {
      final List<Map<String, dynamic>> maps = await database.query('quotes', orderBy: 'date DESC');
      return maps.map((map) => Quote.fromMap(map)).toList();
    } catch (e) {
      debugPrint('获取引用错误: $e');
      return [];
    }
  }
}