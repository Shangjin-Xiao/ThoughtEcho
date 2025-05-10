import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 日志条目模型
class LogEntry {
  final String timestamp;
  final String level;
  final String message;
  final String? source;
  final String? error;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
    this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'level': level,
      'message': message,
      'source': source,
      'error': error,
      'stack_trace': stackTrace,
    };
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      timestamp: map['timestamp'] as String,
      level: map['level'] as String,
      message: map['message'] as String,
      source: map['source'] as String?,
      error: map['error'] as String?,
      stackTrace: map['stack_trace'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory LogEntry.fromJson(String source) =>
      LogEntry.fromMap(json.decode(source));
}

/// 日志存储抽象接口
abstract class LogStorage {
  Future<void> initialize();
  Future<int> insertLog(Map<String, dynamic> log);
  Future<void> insertLogs(List<Map<String, dynamic>> logs);
  Future<List<Map<String, dynamic>>> queryLogs({
    String? level,
    String? searchText,
    String? source,
    String? startDate,
    String? endDate,
    int limit = 100,
    int offset = 0,
    String orderBy = 'timestamp DESC',
  });
  Future<int> getLogCount();
  Future<int> deleteOldLogs(int maxLogCount);
  Future<int> clearAllLogs();
  Future<List<Map<String, dynamic>>> getRecentLogs(int limit);
  Future<void> close();
}

/// Web 平台的日志存储实现（使用 SharedPreferences）
class WebLogStorage implements LogStorage {
  static const String _logStorageKey = 'app_logs_storage';
  static const String _logCountKey = 'app_logs_count';
  late SharedPreferences _prefs;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('Web平台：初始化日志存储 (SharedPreferences)');
  }

  // 从 SharedPreferences 获取所有日志
  Future<List<LogEntry>> _getAllLogs() async {
    final List<String> logStrings = _prefs.getStringList(_logStorageKey) ?? [];
    return logStrings.map((str) => LogEntry.fromJson(str)).toList();
  }

  // 保存所有日志到 SharedPreferences
  Future<void> _saveLogs(List<LogEntry> logs) async {
    final List<String> logStrings = logs.map((log) => log.toJson()).toList();
    await _prefs.setStringList(_logStorageKey, logStrings);
  }

  @override
  Future<int> insertLog(Map<String, dynamic> log) async {
    final logs = await _getAllLogs();
    final logEntry = LogEntry.fromMap(log);
    logs.add(logEntry);

    // 更新计数器
    final count = _prefs.getInt(_logCountKey) ?? 0;
    await _prefs.setInt(_logCountKey, count + 1);

    await _saveLogs(logs);
    return count + 1; // 返回ID
  }

  @override
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    final existingLogs = await _getAllLogs();
    final newLogs = logs.map((log) => LogEntry.fromMap(log)).toList();
    existingLogs.addAll(newLogs);

    // 更新计数器
    final count = _prefs.getInt(_logCountKey) ?? 0;
    await _prefs.setInt(_logCountKey, count + logs.length);

    await _saveLogs(existingLogs);
  }

  @override
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
    var logs = await _getAllLogs();

    // 应用过滤条件
    if (level != null && level.isNotEmpty) {
      logs = logs.where((log) => log.level == level).toList();
    }

    if (searchText != null && searchText.isNotEmpty) {
      logs =
          logs
              .where(
                (log) => log.message.toLowerCase().contains(
                  searchText.toLowerCase(),
                ),
              )
              .toList();
    }

    if (source != null && source.isNotEmpty) {
      logs =
          logs
              .where(
                (log) =>
                    log.source != null &&
                    log.source!.toLowerCase().contains(source.toLowerCase()),
              )
              .toList();
    }

    if (startDate != null) {
      logs =
          logs.where((log) => log.timestamp.compareTo(startDate) >= 0).toList();
    }

    if (endDate != null) {
      logs =
          logs.where((log) => log.timestamp.compareTo(endDate) <= 0).toList();
    }

    // 排序
    if (orderBy.toLowerCase().contains('desc')) {
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // 降序
    } else {
      logs.sort((a, b) => a.timestamp.compareTo(b.timestamp)); // 升序
    }

    // 分页
    final start = offset < logs.length ? offset : logs.length;
    final end = start + limit < logs.length ? start + limit : logs.length;
    logs = logs.sublist(start, end);

    return logs.map((log) => log.toMap()).toList();
  }

  @override
  Future<int> getLogCount() async {
    return _prefs.getInt(_logCountKey) ?? 0;
  }

  @override
  Future<int> deleteOldLogs(int maxLogCount) async {
    var logs = await _getAllLogs();

    if (logs.length <= maxLogCount) {
      return 0;
    }

    // 按时间排序（最旧的在前）
    logs.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final deleteCount = logs.length - maxLogCount;
    logs = logs.sublist(deleteCount); // 保留最新的 maxLogCount 条

    await _saveLogs(logs);
    await _prefs.setInt(_logCountKey, logs.length);

    return deleteCount;
  }

  @override
  Future<int> clearAllLogs() async {
    final count = await getLogCount();
    await _prefs.remove(_logStorageKey);
    await _prefs.remove(_logCountKey);
    return count;
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentLogs(int limit) async {
    var logs = await _getAllLogs();

    // 按时间降序排序（最新的在前）
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 取最新的 limit 条
    logs = logs.take(limit).toList();

    return logs.map((log) => log.toMap()).toList();
  }

  @override
  Future<void> close() async {
    // SharedPreferences 不需要关闭
  }
}

/// 本地平台的日志存储实现（使用 SQLite）
class NativeLogStorage implements LogStorage {
  static const String _logTableName = 'app_logs';
  static const String _logDbName = 'logs.db';
  static const int _dbVersion = 1;

  Database? _database;

  @override
  Future<void> initialize() async {
    if (!kIsWeb) {
      try {
        // 在 Windows 平台上初始化 FFI
        if (Platform.isWindows) {
          debugPrint('Windows平台：初始化 sqflite_ffi');
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        }

        // 确保数据库目录存在
        final appDir = await getApplicationDocumentsDirectory();
        final dbPath = join(appDir.path, 'databases');

        await Directory(dbPath).create(recursive: true);

        final path = join(dbPath, _logDbName);
        debugPrint('Native平台：打开日志数据库 $path');

        _database = await openDatabase(
          path,
          version: _dbVersion,
          onCreate: _createDb,
        );
      } catch (e, stack) {
        debugPrint('初始化日志数据库失败: $e');
        debugPrint('$stack');
        rethrow;
      }
    }
  }

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
      await db.execute(
        'CREATE INDEX log_timestamp_idx ON $_logTableName (timestamp)',
      );
      await db.execute('CREATE INDEX log_level_idx ON $_logTableName (level)');

      debugPrint('日志表创建完成');
    } catch (e, stack) {
      debugPrint('创建日志表失败: $e');
      debugPrint('$stack');
      rethrow;
    }
  }

  // 确保数据库已初始化
  Future<Database> _getDatabase() async {
    if (_database != null) return _database!;
    throw StateError('数据库尚未初始化');
  }

  @override
  Future<int> insertLog(Map<String, dynamic> log) async {
    try {
      final db = await _getDatabase();
      return await db.insert(
        _logTableName,
        log,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('插入日志失败: $e');
      return -1;
    }
  }

  @override
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return;

    try {
      final db = await _getDatabase();
      final batch = db.batch();

      for (final log in logs) {
        batch.insert(
          _logTableName,
          log,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('批量插入日志失败: $e');
    }
  }

  @override
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
      final db = await _getDatabase();

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

      final whereClause =
          conditions.isNotEmpty ? conditions.join(' AND ') : null;

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

  @override
  Future<int> getLogCount() async {
    try {
      final db = await _getDatabase();
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_logTableName',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('获取日志数量失败: $e');
      return 0;
    }
  }

  @override
  Future<int> deleteOldLogs(int maxLogCount) async {
    try {
      final db = await _getDatabase();

      // 获取日志总数
      final count = await getLogCount();

      // 如果超过最大存储数量，则删除最早的日志
      if (count > maxLogCount) {
        final deleteCount = count - maxLogCount;
        await db.execute('''
          DELETE FROM $_logTableName 
          WHERE id IN (
            SELECT id FROM $_logTableName 
            ORDER BY timestamp ASC 
            LIMIT $deleteCount
          )
        ''');

        return deleteCount;
      }

      return 0;
    } catch (e) {
      debugPrint('清理旧日志失败: $e');
      return 0;
    }
  }

  @override
  Future<int> clearAllLogs() async {
    try {
      final db = await _getDatabase();
      return await db.delete(_logTableName);
    } catch (e) {
      debugPrint('清除所有日志失败: $e');
      return 0;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentLogs(int limit) async {
    try {
      final db = await _getDatabase();
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

  @override
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

/// 日志数据库服务 - 负责管理专用于日志的存储
class LogDatabaseService {
  // 单例模式
  static final LogDatabaseService _instance = LogDatabaseService._internal();
  factory LogDatabaseService() => _instance;
  LogDatabaseService._internal();

  // 日志存储实现
  late final LogStorage _storage;
  bool _initialized = false;

  // 获取数据库实例
  Future<void> get ready async {
    if (!_initialized) {
      await _initialize();
    }
  }

  // 初始化日志存储
  Future<void> _initialize() async {
    if (_initialized) return; // 如果已经初始化，直接返回

    try {
      // 确定存储类型
      if (kIsWeb) {
        // 在Web平台上使用SharedPreferences存储
        _storage = WebLogStorage();
      } else {
        // 在原生平台上使用SQLite存储
        _storage = NativeLogStorage();
      }

      // 初始化存储
      await _storage.initialize();

      // 设置初始化完成标志
      _initialized = true;

      // 清理旧日志
      _cleanupOldLogs();
    } catch (e) {
      debugPrint('初始化日志存储失败: $e');
      rethrow; // 重新抛出异常以便上层处理
    }
  }

  // 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _initialize();
    }
  }

  /// 添加日志
  Future<int> insertLog(Map<String, dynamic> log) async {
    await _ensureInitialized();
    return _storage.insertLog(log);
  }

  /// 批量添加日志
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    await _ensureInitialized();
    return _storage.insertLogs(logs);
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
    await _ensureInitialized();
    return _storage.queryLogs(
      level: level,
      searchText: searchText,
      source: source,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
    );
  }

  /// 获取日志数量
  Future<int> getLogCount() async {
    await _ensureInitialized();
    return _storage.getLogCount();
  }

  /// 清除旧日志，保持数据库大小可控
  Future<int> deleteOldLogs(int maxLogCount) async {
    await _ensureInitialized();
    return _storage.deleteOldLogs(maxLogCount);
  }

  /// 清除所有日志
  Future<int> clearAllLogs() async {
    await _ensureInitialized();
    return _storage.clearAllLogs();
  }

  /// 获取最近的日志
  Future<List<Map<String, dynamic>>> getRecentLogs(int limit) async {
    await _ensureInitialized();
    return _storage.getRecentLogs(limit);
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_initialized) {
      await _storage.close();
      _initialized = false;
    }
  }

  /// 清理旧日志
  Future<void> _cleanupOldLogs() async {
    try {
      // 获取日志总数
      final count = await _storage.getLogCount();

      // 如果超过最大限制，删除最旧的日志
      const int maxLogsToKeep = 1000; // 保留最近1000条日志
      if (count > maxLogsToKeep) {
        await _storage.deleteOldLogs(maxLogsToKeep); // 只执行清理，无需记录条数
      }
    } catch (e) {
      debugPrint('清理旧日志失败: $e');
      // 失败不抛出异常，因为这是非关键操作
    }
  }
}
