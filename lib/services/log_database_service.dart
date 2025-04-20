import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 日志数据库服务 - 负责管理专用于日志的SQLite数据库
class LogDatabaseService {
  // 单例模式
  static final LogDatabaseService _instance = LogDatabaseService._internal();
  factory LogDatabaseService() => _instance;
  LogDatabaseService._internal();
  
  static const String _logDbName = 'logs.db';
  static const String _logTableName = 'app_logs';
  static const int _dbVersion = 1;
  
  Database? _database;
  
  // 获取数据库实例，如果不存在则初始化
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  /// 初始化日志数据库
  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      // Web平台使用内存数据库
      debugPrint('Web平台：初始化日志内存数据库');
      return openDatabase(
        inMemoryDatabasePath,
        version: _dbVersion,
        onCreate: _createDb,
      );
    }
    
    try {
      // 获取数据库文件路径
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, 'databases');
      
      // 确保目录存在
      await Directory(dbPath).create(recursive: true);
      final path = join(dbPath, _logDbName);
      
      debugPrint('日志数据库路径: $path');
      
      // 打开数据库
      if (Platform.isWindows) {
        return databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: _dbVersion,
            onCreate: _createDb,
          ),
        );
      } else {
        return openDatabase(
          path,
          version: _dbVersion,
          onCreate: _createDb,
        );
      }
    } catch (e, stack) {
      debugPrint('初始化日志数据库失败: $e');
      debugPrint('$stack');
      rethrow;
    }
  }
  
  /// 创建数据库表
  Future<void> _createDb(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $_logTableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          level TEXT NOT NULL,
          message TEXT NOT NULL,
          source TEXT,
          error TEXT,
          stack_trace TEXT
        )
      ''');
      
      // 创建索引以加速查询
      await db.execute('CREATE INDEX log_timestamp_idx ON $_logTableName (timestamp)');
      await db.execute('CREATE INDEX log_level_idx ON $_logTableName (level)');
      
      debugPrint('日志表创建完成');
    } catch (e, stack) {
      debugPrint('创建日志表失败: $e');
      debugPrint('$stack');
      rethrow;
    }
  }
  
  /// 添加日志
  Future<int> insertLog(Map<String, dynamic> log) async {
    try {
      final db = await database;
      return await db.insert(
        _logTableName, 
        log,
        conflictAlgorithm: ConflictAlgorithm.replace
      );
    } catch (e) {
      debugPrint('插入日志失败: $e');
      return -1;
    }
  }
  
  /// 批量添加日志
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return;
    
    try {
      final db = await database;
      final batch = db.batch();
      
      for (final log in logs) {
        batch.insert(
          _logTableName, 
          log, 
          conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('批量插入日志失败: $e');
    }
  }
  
  /// 查询日志
  Future<List<Map<String, dynamic>>> queryLogs({
    String? level,
    String? searchText,
    String? source,
    String? startDate,
    String? endDate,
    int limit = 100,
    int offset = 0,
    String orderBy = 'timestamp DESC',
  }) async {
    try {
      final db = await database;
      
      // 构建查询条件
      final conditions = <String>[];
      final arguments = <dynamic>[];
      
      if (level != null && level.isNotEmpty) {
        conditions.add('level = ?');
        arguments.add(level);
      }
      
      if (searchText != null && searchText.isNotEmpty) {
        conditions.add('message LIKE ?');
        arguments.add('%$searchText%');
      }
      
      if (source != null && source.isNotEmpty) {
        conditions.add('source LIKE ?');
        arguments.add('%$source%');
      }
      
      if (startDate != null) {
        conditions.add('timestamp >= ?');
        arguments.add(startDate);
      }
      
      if (endDate != null) {
        conditions.add('timestamp <= ?');
        arguments.add(endDate);
      }
      
      final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;
      
      // 执行查询
      return await db.query(
        _logTableName,
        where: whereClause,
        whereArgs: arguments.isNotEmpty ? arguments : null,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      debugPrint('查询日志失败: $e');
      return [];
    }
  }
  
  /// 获取日志数量
  Future<int> getLogCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_logTableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('获取日志数量失败: $e');
      return 0;
    }
  }
  
  /// 清除旧日志，保持数据库大小可控
  Future<int> deleteOldLogs(int maxLogCount) async {
    try {
      final db = await database;
      
      // 获取日志总数
      final count = await getLogCount();
      
      // 如果超过最大存储数量，则删除最早的日志
      if (count > maxLogCount) {
        final deleteCount = count - maxLogCount;
        final result = await db.execute('''
          DELETE FROM $_logTableName 
          WHERE id IN (
            SELECT id FROM $_logTableName 
            ORDER BY timestamp ASC 
            LIMIT $deleteCount
          )
        ''');
        
        debugPrint('清理了 $deleteCount 条旧日志');
        return deleteCount;
      }
      
      return 0;
    } catch (e) {
      debugPrint('清理旧日志失败: $e');
      return 0;
    }
  }
  
  /// 清除所有日志
  Future<int> clearAllLogs() async {
    try {
      final db = await database;
      return await db.delete(_logTableName);
    } catch (e) {
      debugPrint('清除所有日志失败: $e');
      return 0;
    }
  }
  
  /// 获取最近的日志
  Future<List<Map<String, dynamic>>> getRecentLogs(int limit) async {
    try {
      final db = await database;
      return await db.query(
        _logTableName,
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('获取最近日志失败: $e');
      return [];
    }
  }
  
  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}