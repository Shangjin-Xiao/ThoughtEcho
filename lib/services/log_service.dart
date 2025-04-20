import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mind_trace/utils/mmkv_ffi_fix.dart';
import 'package:mind_trace/services/log_database_service.dart';

// 定义日志级别
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  none, // 不记录任何日志
}

/// 日志条目类，表示单条日志记录
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
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
  
  /// 从数据库行创建日志条目
  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      timestamp: DateTime.parse(map['timestamp'] as String),
      level: LogLevel.values.firstWhere(
        (l) => l.name == (map['level'] as String),
        orElse: () => LogLevel.info,
      ),
      message: map['message'] as String,
      source: map['source'] as String?,
      error: map['error'] as String?,
      stackTrace: map['stack_trace'] as String?,
    );
  }
  
  /// 转换为数据库可用的映射
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      'source': source,
      'error': error,
      'stack_trace': stackTrace,
    };
  }
  
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('${timestamp.toIso8601String()} [${level.name.toUpperCase()}]');
    
    if (source != null && source!.isNotEmpty) {
      buffer.write(' [$source]');
    }
    
    buffer.write(' $message');
    
    if (error != null && error!.isNotEmpty) {
      buffer.write('\nError: $error');
    }
    
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buffer.write('\nStackTrace: $stackTrace');
    }
    
    return buffer.toString();
  }
}

/// 日志服务 - 负责记录和管理应用日志
class LogService with ChangeNotifier {
  static const String _logLevelKey = 'log_level';
  static const int _maxInMemoryLogs = 300; // 内存中保留的最大日志数量
  static const int _maxStoredLogs = 10000; // 数据库中存储的最大日志数
  static const Duration _batchSaveInterval = Duration(seconds: 2); // 批量保存日志的间隔时间
  
  // 日志数据库服务
  final LogDatabaseService _logDb = LogDatabaseService();
  
  LogLevel _currentLevel = LogLevel.info; // 默认级别
  bool _initialized = false;
  
  // 内存中的日志缓存（最新的日志）
  List<LogEntry> _memoryLogs = [];
  // 待写入数据库的日志
  final List<LogEntry> _pendingLogs = [];
  // 批量写入计时器
  Timer? _batchSaveTimer;
  
  // 提供只读访问
  List<LogEntry> get logs => List.unmodifiable(_memoryLogs);
  LogLevel get currentLevel => _currentLevel;
  
  /// 创建日志服务实例
  LogService() {
    _initialize();
  }
  
  /// 初始化日志服务
  Future<void> _initialize() async {
    if (_initialized) return;
    
    try {
      // 初始化 SafeMMKV 并加载日志级别设置
      final mmkv = SafeMMKV();
      await mmkv.initialize();
      
      // 从 MMKV 加载日志级别
      final levelIndex = mmkv.getInt(_logLevelKey) ?? LogLevel.info.index;
      if (levelIndex >= 0 && levelIndex < LogLevel.values.length) {
        _currentLevel = LogLevel.values[levelIndex];
      } else {
        _currentLevel = LogLevel.info;
        await mmkv.setInt(_logLevelKey, _currentLevel.index);
      }
      
      // 启动批量保存定时器
      _startBatchSaveTimer();
      
      // 从数据库加载最近的日志
      await _loadRecentLogs();
      
      _initialized = true;
      
      // 记录服务已启动的信息
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: '日志服务已启动',
        source: 'LogService',
      ));
      
    } catch (e, stack) {
      debugPrint('日志服务初始化失败: $e');
      debugPrint('$stack');
      
      // 初始化失败也设置为已初始化，避免重复尝试
      _initialized = true;
      _currentLevel = LogLevel.info;
      
      // 记录错误但不会导致递归
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: '日志服务初始化失败: $e',
        error: e.toString(),
        stackTrace: stack.toString(),
        source: 'LogService',
      ));
    }
  }

  /// 从数据库加载最近的日志
  Future<void> _loadRecentLogs() async {
    try {
      final results = await _logDb.getRecentLogs(100); // 加载最新的100条日志
      
      if (results.isNotEmpty) {
        final loadedLogs = results.map((row) => LogEntry.fromMap(row)).toList();
        
        // 保留最新的日志
        loadedLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _memoryLogs = loadedLogs;
        
        notifyListeners();
        debugPrint('从数据库加载了 ${_memoryLogs.length} 条日志');
      }
    } catch (e) {
      debugPrint('从数据库加载日志失败: $e');
    }
  }
  
  /// 启动批量保存定时器
  void _startBatchSaveTimer() {
    _batchSaveTimer?.cancel();
    _batchSaveTimer = Timer.periodic(_batchSaveInterval, (_) {
      _savePendingLogsToDatabase();
    });
  }
  
  /// 添加日志条目到内存缓存和待处理队列
  void _addLogEntry(LogEntry entry) {
    // 添加到内存缓存，保持最新的日志在前面
    _memoryLogs.insert(0, entry);
    
    // 如果内存缓存超过限制，移除较早的日志
    if (_memoryLogs.length > _maxInMemoryLogs) {
      _memoryLogs.removeLast();
    }
    
    // 添加到待处理队列，准备写入数据库
    _pendingLogs.add(entry);
    
    // 在调试模式下打印日志
    if (kDebugMode) {
      print(entry.toString());
    }
    
    // 通知监听器
    notifyListeners();
  }
  
  /// 将待处理的日志保存到数据库
  Future<void> _savePendingLogsToDatabase() async {
    if (_pendingLogs.isEmpty) return;
    
    try {
      // 复制待处理日志列表，并清空原列表
      final logsToSave = List<LogEntry>.from(_pendingLogs);
      _pendingLogs.clear();
      
      // 批量插入日志
      await _logDb.insertLogs(logsToSave.map((log) => log.toMap()).toList());
      
      // 定期清理旧日志
      await _logDb.deleteOldLogs(_maxStoredLogs);
      
    } catch (e) {
      debugPrint('保存日志到数据库失败: $e');
      
      // 保存失败时，将日志重新加入待处理队列（但避免队列过长）
      if (_pendingLogs.length < 100) {
        _pendingLogs.addAll(_pendingLogs);
      }
    }
  }
  
  /// 设置新的日志级别并保存
  Future<void> setLogLevel(LogLevel newLevel) async {
    if (_currentLevel != newLevel) {
      final oldLevel = _currentLevel;
      _currentLevel = newLevel;
      
      try {
        final mmkv = SafeMMKV();
        await mmkv.setInt(_logLevelKey, newLevel.index);
        
        log(
          LogLevel.info,
          '日志级别已从 ${oldLevel.name} 更改为 ${newLevel.name}',
          source: 'LogService'
        );
      } catch (e) {
        debugPrint('设置日志级别失败: $e');
        log(
          LogLevel.error,
          '设置日志级别失败',
          error: e.toString(),
          source: 'LogService'
        );
      }
      
      notifyListeners();
    }
  }
  
  /// 清除所有内存中的日志
  void clearMemoryLogs() {
    _memoryLogs.clear();
    notifyListeners();
    log(LogLevel.info, '内存中的日志已清除', source: 'LogService');
  }
  
  /// 清除所有存储的日志（包括数据库中的）
  Future<void> clearAllLogs() async {
    // 清除内存中的日志
    _memoryLogs.clear();
    _pendingLogs.clear();
    
    // 清除数据库中的日志
    await _logDb.clearAllLogs();
    
    notifyListeners();
    
    // 记录一条新日志表示清除操作完成
    log(LogLevel.info, '所有日志记录已清除', source: 'LogService');
  }
  
  /// 查询日志（从数据库）
  Future<List<LogEntry>> queryLogs({
    LogLevel? level,
    String? searchText,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final results = await _logDb.queryLogs(
        level: level?.name,
        searchText: searchText,
        source: source,
        startDate: startDate?.toIso8601String(),
        endDate: endDate?.toIso8601String(),
        limit: limit,
        offset: offset,
      );
      
      return results.map((row) => LogEntry.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询日志失败: $e');
      return [];
    }
  }

  /// 记录日志的方法
  void log(
    LogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace
  }) {
    // 确保已初始化
    if (!_initialized) {
      // 加入队列，待初始化完成后处理
      _initialize().then((_) {
        log(level, message, source: source, error: error, stackTrace: stackTrace);
      });
      return;
    }
    
    // 只有当消息的级别大于或等于当前设置的级别时才记录
    if (level.index >= _currentLevel.index && _currentLevel != LogLevel.none) {
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        level: level,
        message: message,
        source: source,
        error: error?.toString(),
        stackTrace: stackTrace?.toString(),
      ));
    }
  }

  /// 销毁时释放资源
  @override
  void dispose() {
    _batchSaveTimer?.cancel();
    _savePendingLogsToDatabase(); // 保存剩余的待处理日志
    super.dispose();
  }

  // 提供便捷的日志记录方法
  void verbose(String message, {String? source, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.verbose, message, source: source, error: error, stackTrace: stackTrace);
      
  void debug(String message, {String? source, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.debug, message, source: source, error: error, stackTrace: stackTrace);
      
  void info(String message, {String? source, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.info, message, source: source, error: error, stackTrace: stackTrace);
      
  void warning(String message, {String? source, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.warning, message, source: source, error: error, stackTrace: stackTrace);
      
  void error(String message, {String? source, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.error, message, source: source, error: error, stackTrace: stackTrace);
}
