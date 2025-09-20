import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
// 为桌面平台启用 FFI 支持（Linux/macOS/Windows）
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
    logDebug('Web平台：初始化日志存储 (SharedPreferences)');
  }

  // 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  // 从 SharedPreferences 获取所有日志
  Future<List<LogEntry>> _getAllLogs() async {
    await _ensureInitialized();
    final List<String> logStrings = _prefs.getStringList(_logStorageKey) ?? [];
    return logStrings.map((str) => LogEntry.fromJson(str)).toList();
  }

  // 保存所有日志到 SharedPreferences
  Future<void> _saveLogs(List<LogEntry> logs) async {
    await _ensureInitialized();
    final List<String> logStrings = logs.map((log) => log.toJson()).toList();
    await _prefs.setStringList(_logStorageKey, logStrings);
  }

  @override
  Future<int> insertLog(Map<String, dynamic> log) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
      logs = logs
          .where(
            (log) => log.message.toLowerCase().contains(
                  searchText.toLowerCase(),
                ),
          )
          .toList();
    }

    if (source != null && source.isNotEmpty) {
      logs = logs
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
    await _ensureInitialized();
    return _prefs.getInt(_logCountKey) ?? 0;
  }

  @override
  Future<int> deleteOldLogs(int maxLogCount) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
        // 修复：确保在桌面平台使用 FFI 数据库工厂（Linux/macOS/Windows）
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          // 如果当前数据库工厂不是 FFI，则进行初始化
          if (databaseFactory != databaseFactoryFfi) {
            sqfliteFfiInit();
            databaseFactory = databaseFactoryFfi;
          }
        }

        // 修复：使用与主数据库一致的路径策略
        // 优先使用主数据库设置的路径，确保一致性
        String dbPath;
        try {
          // 首选：获取主数据库设置的路径（与main.dart保持一致）
          final appDir = await getApplicationDocumentsDirectory();
          dbPath = join(appDir.path, 'databases');
        } catch (e) {
          // 回退：使用系统数据库路径
          dbPath = await getDatabasesPath();
          logDebug('无法获取应用文档目录，回退到系统数据库路径: $dbPath');
        }
        
        // 确保目录存在
        await Directory(dbPath).create(recursive: true);
        final logDbPath = join(dbPath, _logDbName);
        
        logDebug('Native平台：使用统一的日志数据库路径 $logDbPath');

        // 尝试从多个可能的位置迁移旧的日志数据库
        await _migrateOldLogDatabase(logDbPath);

        _database = await openDatabase(
          logDbPath,
          version: _dbVersion,
          onCreate: _createDb,
          onOpen: (db) async {
            // 启用WAL以提升可靠性（特别是Android）
            try {
              await db.execute('PRAGMA journal_mode=WAL;');
              await db.execute('PRAGMA synchronous=NORMAL;');
            } catch (_) {}
          },
        );
      } catch (e, stack) {
        logDebug('初始化日志数据库失败: $e');
        logDebug('$stack');
        rethrow;
      }
    }
  }

  /// 迁移旧的日志数据库文件到新的统一路径
  Future<void> _migrateOldLogDatabase(String targetPath) async {
    try {
      // 如果目标数据库已存在，无需迁移
      if (await File(targetPath).exists()) {
        return;
      }

      // 检查可能的旧路径
      final List<String> possibleOldPaths = [];
      
      try {
        // 旧路径1：系统数据库路径
        final systemDbDir = await getDatabasesPath();
        possibleOldPaths.add(join(systemDbDir, _logDbName));
      } catch (_) {}

      try {
        // 旧路径2：应用文档目录（没有databases子目录）
        final appDir = await getApplicationDocumentsDirectory();
        possibleOldPaths.add(join(appDir.path, _logDbName));
      } catch (_) {}

      // 查找并迁移第一个存在的旧数据库
      for (final oldPath in possibleOldPaths) {
        if (await File(oldPath).exists()) {
          logDebug('发现旧日志数据库，正在迁移：$oldPath -> $targetPath');
          
          try {
            // 复制文件而非移动，确保安全
            await File(oldPath).copy(targetPath);
            
            // 验证迁移是否成功
            if (await File(targetPath).exists()) {
              // 删除旧文件
              await File(oldPath).delete();
              logDebug('日志数据库迁移成功');
              break;
            }
          } catch (e) {
            logDebug('迁移日志数据库失败: $e，将使用新数据库');
            // 迁移失败时删除可能损坏的目标文件
            try {
              await File(targetPath).delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      logDebug('检查旧日志数据库迁移时出错: $e');
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

      logDebug('日志表创建完成，数据库路径: ${db.path}');
    } catch (e, stack) {
      logDebug('创建日志表失败: $e');
      logDebug('$stack');
      rethrow;
    }
  }

  // 确保数据库已初始化
  Future<Database> _getDatabase() async {
    if (_database != null) return _database!;
    throw StateError('数据库尚未初始化');
  }

  // 暴露数据库访问方法供状态检查使用
  Future<Database> getDatabase() async {
    return await _getDatabase();
  }

  @override
  Future<int> insertLog(Map<String, dynamic> log) async {
    try {
      final db = await _getDatabase();
      final result = await db.insert(
        _logTableName,
        log,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return result;
    } catch (e, stackTrace) {
      logDebug('插入日志失败: $e');
      logDebug('堆栈跟踪: $stackTrace');
      
      // 记录失败日志的详细信息
      logDebug('失败日志详情: level=${log['level']}, '
              'message长度=${log['message']?.toString().length ?? 0}, '
              'timestamp=${log['timestamp']}, '
              'source=${log['source']}');
      
      return -1;
    }
  }

  @override
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return;

    try {
      final db = await _getDatabase();
      
      // 记录批量插入的统计信息
      logDebug('开始批量插入 ${logs.length} 条日志记录');
      
      final batch = db.batch();

      for (final log in logs) {
        batch.insert(
          _logTableName,
          log,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final results = await batch.commit(noResult: false);
      logDebug('批量插入完成，成功插入 ${results.length} 条日志记录');
    } catch (e, stackTrace) {
      logDebug('批量插入日志失败: $e');
      logDebug('堆栈跟踪: $stackTrace');
      
      // 在Android上，尝试逐条插入以确定具体哪条日志有问题
      if (!kIsWeb && Platform.isAndroid && logs.length > 1) {
        logDebug('尝试逐条插入以诊断问题...');
        int successCount = 0;
        int failureCount = 0;
        
        for (int i = 0; i < logs.length; i++) {
          try {
            await insertLog(logs[i]);
            successCount++;
          } catch (singleError) {
            failureCount++;
            logDebug('第 ${i+1} 条日志插入失败: $singleError');
            
            // 记录问题日志的详细信息
            final problemLog = logs[i];
            logDebug('问题日志内容: level=${problemLog['level']}, '
                    'message长度=${problemLog['message']?.toString().length ?? 0}, '
                    'timestamp=${problemLog['timestamp']}');
          }
        }
        
        logDebug('逐条插入结果: 成功 $successCount 条, 失败 $failureCount 条');
      }
      
      rethrow;
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
      logDebug('查询日志失败: $e');
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
      logDebug('获取日志数量失败: $e');
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
      logDebug('清理旧日志失败: $e');
      return 0;
    }
  }

  @override
  Future<int> clearAllLogs() async {
    try {
      final db = await _getDatabase();
      return await db.delete(_logTableName);
    } catch (e) {
      logDebug('清除所有日志失败: $e');
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
      logDebug('获取最近日志失败: $e');
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
  LogStorage? _storage;
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
      await _storage!.initialize();

      // 设置初始化完成标志
      _initialized = true;

      // 清理旧日志
      _cleanupOldLogs();
    } catch (e) {
      logDebug('初始化日志存储失败: $e');
      rethrow; // 重新抛出异常以便上层处理
    }
  }

  // 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _initialize();
    }
  }

  /// 获取日志数据库的状态信息（用于调试）
  Future<Map<String, dynamic>> getDatabaseStatus() async {
    final status = <String, dynamic>{
      'initialized': _initialized,
      'storage_type': kIsWeb ? 'SharedPreferences' : 'SQLite',
    };

    if (_initialized && _storage != null) {
      try {
        final logCount = await _storage!.getLogCount();
        status['log_count'] = logCount;

        if (!kIsWeb && _storage is NativeLogStorage) {
          final nativeStorage = _storage as NativeLogStorage;
          final db = await nativeStorage.getDatabase();
          status['database_path'] = db.path;
          status['database_version'] = await db.getVersion();
          
          // 检查表是否存在
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='app_logs'",
          );
          status['table_exists'] = tables.isNotEmpty;
        }
      } catch (e) {
        status['error'] = e.toString();
      }
    }

    return status;
  }

  /// 批量添加日志
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    await _ensureInitialized();
    return _storage!.insertLogs(logs);
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
    return _storage!.queryLogs(
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
    return _storage!.getLogCount();
  }

  /// 清除旧日志，保持数据库大小可控
  Future<int> deleteOldLogs(int maxLogCount) async {
    await _ensureInitialized();
    return _storage!.deleteOldLogs(maxLogCount);
  }

  /// 清除所有日志
  Future<int> clearAllLogs() async {
    await _ensureInitialized();
    return _storage!.clearAllLogs();
  }

  /// 获取最近的日志
  Future<List<Map<String, dynamic>>> getRecentLogs(int limit) async {
    await _ensureInitialized();
    return _storage!.getRecentLogs(limit);
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_initialized && _storage != null) {
      await _storage!.close();
      _initialized = false;
    }
  }

  /// 清理旧日志
  Future<void> _cleanupOldLogs() async {
    try {
      // 获取日志总数
      final count = await _storage!.getLogCount();

      // 如果超过最大限制，删除最旧的日志
      const int maxLogsToKeep = 1000; // 保留最近1000条日志
      if (count > maxLogsToKeep) {
        await _storage!.deleteOldLogs(maxLogsToKeep); // 只执行清理，无需记录条数
      }
    } catch (e) {
      logDebug('清理旧日志失败: $e');
      // 失败不抛出异常，因为这是非关键操作
    }
  }
}
