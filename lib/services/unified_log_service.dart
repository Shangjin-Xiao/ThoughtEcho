import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;
import 'package:logging_flutter/logging_flutter.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/services/log_database_service.dart';
import 'package:flutter/widgets.dart';

// 导入main.dart中的全局函数
import '../main.dart' show getAndClearDeferredErrors;

// 定义日志级别映射
enum UnifiedLogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  none, // 不记录任何日志
}

/// 统一日志条目类，表示单条日志记录
class LogEntry {
  final DateTime timestamp;
  final UnifiedLogLevel level;
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
      level: UnifiedLogLevel.values.firstWhere(
        (l) => l.name == (map['level'] as String),
        orElse: () => UnifiedLogLevel.info,
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

/// 统一日志服务 - 整合 logging_flutter 和现有日志系统
class UnifiedLogService with ChangeNotifier {
  static const String _logLevelKey = 'log_level';
  static const int _maxInMemoryLogs = 300;
  static const int _maxStoredLogs = 500;
  static const Duration _batchSaveInterval = Duration(seconds: 2);

  // 单例实例
  static UnifiedLogService? _instance;
  
  // logging_flutter 的 logger
  late logging.Logger _logger;
  
  // 日志数据库服务
  final LogDatabaseService _logDb = LogDatabaseService();
  
  UnifiedLogLevel _currentLevel = UnifiedLogLevel.info;
  bool _initialized = false;
  
  // 内存中的日志缓存
  List<LogEntry> _memoryLogs = [];
  // 待写入数据库的日志
  final List<LogEntry> _pendingLogs = [];
  // 批量写入计时器
  Timer? _batchSaveTimer;
  
  // 提供只读访问
  List<LogEntry> get logs => List.unmodifiable(_memoryLogs);
  UnifiedLogLevel get currentLevel => _currentLevel;

  // 标志位，防止重复调度 postFrameCallback
  bool _notifyScheduled = false;
  
  /// 单例模式访问
  static UnifiedLogService get instance {
    _instance ??= UnifiedLogService();
    return _instance!;
  }

  /// 创建统一日志服务实例
  UnifiedLogService() {
    _initialize();
  }
  
  /// 初始化统一日志服务
  Future<void> _initialize() async {
    if (_initialized) return;
    
    try {
      // 初始化 logging_flutter
      await _initializeLoggingFlutter();
      
      // 初始化 SafeMMKV 并加载日志级别设置
      final mmkv = SafeMMKV();
      await mmkv.initialize();
      
      // 从 MMKV 加载日志级别
      final levelIndex = mmkv.getInt(_logLevelKey);
      if (levelIndex != null && levelIndex >= 0 && levelIndex < UnifiedLogLevel.values.length) {
        _currentLevel = UnifiedLogLevel.values[levelIndex];
      } else {
        _currentLevel = UnifiedLogLevel.info;
        await mmkv.setInt(_logLevelKey, _currentLevel.index);
      }
      
      // 设置 logging_flutter 的日志级别
      _updateLoggingFlutterLevel();
      
      // 启动批量保存定时器
      _startBatchSaveTimer();
      
      // 从数据库加载最近的日志
      await _loadRecentLogs();
      
      _initialized = true;
      
      // 记录服务已启动的信息
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        level: _currentLevel,
        message: '统一日志服务已启动，当前日志级别: ${_currentLevel.name}',
        source: 'UnifiedLogService',
      ));

      // 处理缓存的早期错误
      _processDeferredErrors();
      
    } catch (e, stack) {
      // 使用 logging_flutter 记录初始化错误
      _logger.severe('统一日志服务初始化失败: $e', e, stack);
      
      _initialized = true;
      _currentLevel = UnifiedLogLevel.info;
      
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        level: UnifiedLogLevel.error,
        message: '统一日志服务初始化失败: $e',
        error: e.toString(),
        stackTrace: stack.toString(),
        source: 'UnifiedLogService',
      ));
    }
  }

  /// 初始化 logging_flutter
  Future<void> _initializeLoggingFlutter() async {
    // 关键修复：启用分层日志记录
    logging.hierarchicalLoggingEnabled = true;
    
    // 设置全局日志级别
    logging.Logger.root.level = logging.Level.ALL;
    
    // 创建应用专用的 logger
    _logger = logging.Logger('ThoughtEcho');
    
    // 添加控制台输出处理器
    logging.Logger.root.onRecord.listen((record) {
      // 只在调试模式下输出到控制台
      if (kDebugMode) {
        final time = record.time.toIso8601String();
        final level = record.level.name;
        final loggerName = record.loggerName;
        final message = record.message;
        
        String logOutput = '[$time] [$level] [$loggerName] $message';
        
        if (record.error != null) {
          logOutput += '\nError: ${record.error}';
        }
        
        if (record.stackTrace != null) {
          logOutput += '\nStackTrace: ${record.stackTrace}';
        }
        
        // 使用原始 print 输出，避免递归
        print(logOutput);
      }
      
      // 将 logging_flutter 的日志也添加到我们的日志系统中
      _addLogEntryFromLoggingRecord(record);
    });
  }

  /// 将 logging.LogRecord 转换为我们的 LogEntry
  void _addLogEntryFromLoggingRecord(logging.LogRecord record) {
    final level = _mapLoggingLevelToUnified(record.level);
    
    _addLogEntry(LogEntry(
      timestamp: record.time,
      level: level,
      message: record.message,
      source: record.loggerName,
      error: record.error?.toString(),
      stackTrace: record.stackTrace?.toString(),
    ));
  }

  /// 映射 logging.Level 到 UnifiedLogLevel
  UnifiedLogLevel _mapLoggingLevelToUnified(logging.Level level) {
    if (level.value >= logging.Level.SEVERE.value) {
      return UnifiedLogLevel.error;
    } else if (level.value >= logging.Level.WARNING.value) {
      return UnifiedLogLevel.warning;
    } else if (level.value >= logging.Level.INFO.value) {
      return UnifiedLogLevel.info;
    } else if (level.value >= logging.Level.CONFIG.value) {
      return UnifiedLogLevel.debug;
    } else {
      return UnifiedLogLevel.verbose;
    }
  }

  /// 映射 UnifiedLogLevel 到 logging.Level
  logging.Level _mapUnifiedLevelToLogging(UnifiedLogLevel level) {
    switch (level) {
      case UnifiedLogLevel.verbose:
        return logging.Level.FINEST;
      case UnifiedLogLevel.debug:
        return logging.Level.FINE;
      case UnifiedLogLevel.info:
        return logging.Level.INFO;
      case UnifiedLogLevel.warning:
        return logging.Level.WARNING;
      case UnifiedLogLevel.error:
        return logging.Level.SEVERE;
      case UnifiedLogLevel.none:
        return logging.Level.OFF;
    }
  }

  /// 更新 logging_flutter 的日志级别
  void _updateLoggingFlutterLevel() {
    final loggingLevel = _mapUnifiedLevelToLogging(_currentLevel);
    _logger.level = loggingLevel;
    // 注意：不要设置 root logger 的级别，因为我们已经启用了分层日志记录
  }
}
