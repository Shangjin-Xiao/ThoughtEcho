import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/services/log_database_service.dart';
import 'package:thoughtecho/services/log_service.dart' as old_log;
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

// 兼容性：映射到旧的 LogLevel
extension UnifiedLogLevelCompat on UnifiedLogLevel {
  old_log.LogLevel get toOldLogLevel {
    switch (this) {
      case UnifiedLogLevel.verbose:
        return old_log.LogLevel.verbose;
      case UnifiedLogLevel.debug:
        return old_log.LogLevel.debug;
      case UnifiedLogLevel.info:
        return old_log.LogLevel.info;
      case UnifiedLogLevel.warning:
        return old_log.LogLevel.warning;
      case UnifiedLogLevel.error:
        return old_log.LogLevel.error;
      case UnifiedLogLevel.none:
        return old_log.LogLevel.none;
    }
  }
}

// 兼容性：从旧的 LogLevel 映射
extension OldLogLevelCompat on old_log.LogLevel {
  UnifiedLogLevel get toUnifiedLogLevel {
    switch (this) {
      case old_log.LogLevel.verbose:
        return UnifiedLogLevel.verbose;
      case old_log.LogLevel.debug:
        return UnifiedLogLevel.debug;
      case old_log.LogLevel.info:
        return UnifiedLogLevel.info;
      case old_log.LogLevel.warning:
        return UnifiedLogLevel.warning;
      case old_log.LogLevel.error:
        return UnifiedLogLevel.error;
      case old_log.LogLevel.none:
        return UnifiedLogLevel.none;
    }
  }
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
      timestamp: _parseTimestamp(map['timestamp']),
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

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw is DateTime) {
      return raw;
    }

    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }

    if (raw is double) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      DateTime? parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return parsed;
      }

      // 常见的非标准格式处理
      final isoCandidate = trimmed.replaceFirst(' ', 'T');
      parsed = DateTime.tryParse(isoCandidate);
      if (parsed != null) {
        return parsed;
      }

      final fallbackCandidate = trimmed.replaceAll('/', '-');
      parsed = DateTime.tryParse(fallbackCandidate);
      if (parsed != null) {
        return parsed;
      }

      final millis = int.tryParse(trimmed);
      if (millis != null) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }

    return DateTime.now();
  }

  /// 从旧的 LogEntry 创建
  factory LogEntry.fromOldLogEntry(old_log.LogEntry oldEntry) {
    return LogEntry(
      timestamp: oldEntry.timestamp,
      level: oldEntry.level.toUnifiedLogLevel,
      message: oldEntry.message,
      source: oldEntry.source,
      error: oldEntry.error,
      stackTrace: oldEntry.stackTrace,
    );
  }

  /// 转换为旧的 LogEntry
  old_log.LogEntry toOldLogEntry() {
    return old_log.LogEntry(
      timestamp: timestamp,
      level: level.toOldLogLevel,
      message: message,
      source: source,
      error: error,
      stackTrace: stackTrace,
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
    buffer.write(
      '${timestamp.toIso8601String()} [${level.name.toUpperCase()}]',
    );

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
class UnifiedLogService with ChangeNotifier, WidgetsBindingObserver {
  static const String _logLevelKey = 'log_level';
  static const String _logLevelUserSetKey = 'log_level_user_set'; // 标记用户是否手动设置过
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
  // 初始化完成通知
  Completer<void>? _initCompleter;

  // 内存中的日志缓存
  List<LogEntry> _memoryLogs = [];
  // 待写入数据库的日志
  final List<LogEntry> _pendingLogs = [];
  // 初始化前暂存的日志，避免竞态
  final List<LogEntry> _bufferDuringInit = [];
  // 批量写入计时器
  Timer? _batchSaveTimer;

  // 日志统计信息
  final Map<UnifiedLogLevel, int> _logStats = {};
  DateTime? _lastLogTime;

  // 提供只读访问
  List<LogEntry> get logs => List.unmodifiable(_memoryLogs);
  UnifiedLogLevel get currentLevel => _currentLevel;
  Map<UnifiedLogLevel, int> get logStats => Map.unmodifiable(_logStats);
  DateTime? get lastLogTime => _lastLogTime;

  // 兼容性：提供旧接口
  List<old_log.LogEntry> get oldLogs =>
      _memoryLogs.map((e) => e.toOldLogEntry()).toList();
  old_log.LogLevel get oldCurrentLevel => _currentLevel.toOldLogLevel;

  // 标志位，防止重复调度 postFrameCallback
  bool _notifyScheduled = false;

  // 标志位，防止日志记录的无限递归
  bool _isLogging = false;

  // 日志性能监控
  int _logOperationCount = 0;
  DateTime? _lastPerformanceReset;
  final Map<String, int> _sourceStats = {};

  /// 单例模式访问
  static UnifiedLogService get instance {
    _instance ??= UnifiedLogService();
    return _instance!;
  }

  /// 创建统一日志服务实例
  UnifiedLogService() {
    _initialize();
    // 监听应用生命周期，确保在后台/退出前刷新日志到数据库
    WidgetsBinding.instance.addObserver(this);
  }

  /// 初始化统一日志服务
  Future<void> _initialize() async {
    if (_initialized) return;
    // 并发保护：如果已在初始化，等待完成
    if (_initCompleter != null) {
      try {
        await _initCompleter!.future;
      } catch (_) {}
      return;
    }

    try {
      _initCompleter = Completer<void>();
      // 初始化 logging_flutter
      await _initializeLoggingFlutter();

      // 初始化 SafeMMKV 并加载日志级别设置
      final mmkv = SafeMMKV();
      await mmkv.initialize();

      // 从 MMKV 加载日志级别
      final levelIndex = mmkv.getInt(_logLevelKey);
      // 检查用户是否手动设置过日志级别
      final userHasSetLevel = mmkv.getBool(_logLevelUserSetKey) ?? false;

      if (levelIndex != null &&
          levelIndex >= 0 &&
          levelIndex < UnifiedLogLevel.values.length) {
        _currentLevel = UnifiedLogLevel.values[levelIndex];

        // 只有当用户没有手动设置过日志级别时，才自动重置为 info
        // 如果用户手动设置了 verbose/debug，则尊重用户的选择
        if (!userHasSetLevel &&
            (_currentLevel == UnifiedLogLevel.verbose ||
                _currentLevel == UnifiedLogLevel.debug)) {
          if (kDebugMode) {
            print(
              'UnifiedLogService: 检测到日志级别为${_currentLevel.name}，用户未手动设置，重置为info',
            );
          }
          _currentLevel = UnifiedLogLevel.info;
          await mmkv.setInt(_logLevelKey, _currentLevel.index);
        }
      } else {
        // 首次启动或无效值时，使用默认的info级别
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
      // 将初始化前缓存的日志入列
      if (_bufferDuringInit.isNotEmpty) {
        for (final entry in List<LogEntry>.from(_bufferDuringInit)) {
          _addLogEntry(entry);
        }
        _bufferDuringInit.clear();
      }
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }

      // 记录服务已启动的信息
      _addLogEntry(
        LogEntry(
          timestamp: DateTime.now(),
          level: _currentLevel,
          message: '统一日志服务已启动，当前日志级别: ${_currentLevel.name}',
          source: 'UnifiedLogService',
        ),
      );

      // 处理缓存的早期错误
      _processDeferredErrors();
    } catch (e, stack) {
      // 使用 logging_flutter 记录初始化错误
      _logger.severe('统一日志服务初始化失败: $e', e, stack);

      _initialized = true;
      _currentLevel = UnifiedLogLevel.info;

      // 即使失败也要完成 completer，避免等待卡死
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }

      _addLogEntry(
        LogEntry(
          timestamp: DateTime.now(),
          level: UnifiedLogLevel.error,
          message: '统一日志服务初始化失败: $e',
          error: e.toString(),
          stackTrace: stack.toString(),
          source: 'UnifiedLogService',
        ),
      );
    }
  }

  /// 初始化 logging_flutter
  Future<void> _initializeLoggingFlutter() async {
    // 关键修复：启用分层日志记录
    logging.hierarchicalLoggingEnabled = true;

    // 修复：设置全局日志级别为 INFO，而不是 ALL
    // 这样默认情况下不会输出过于详细的 verbose/debug 日志
    logging.Logger.root.level = logging.Level.INFO;

    // 创建应用专用的 logger
    _logger = logging.Logger('ThoughtEcho');

    // 添加控制台输出处理器
    logging.Logger.root.onRecord.listen((record) {
      // 防止递归：如果正在记录日志，跳过
      if (_isLogging) return;

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

        // 使用 debugPrint 输出到控制台，避免递归
        if (kDebugMode) {
          // 在调试模式下输出到控制台
          // ignore: avoid_print
          print(logOutput);
        }
      }

      // 将 logging_flutter 的日志也添加到我们的日志系统中
      _addLogEntryFromLoggingRecord(record);
    });
  }

  /// 将 logging.LogRecord 转换为我们的 LogEntry
  void _addLogEntryFromLoggingRecord(logging.LogRecord record) {
    final level = _mapLoggingLevelToUnified(record.level);

    _addLogEntry(
      LogEntry(
        timestamp: record.time,
        level: level,
        message: record.message,
        source: record.loggerName,
        error: record.error?.toString(),
        stackTrace: record.stackTrace?.toString(),
      ),
    );
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

  /// 从数据库加载最近的日志
  Future<void> _loadRecentLogs() async {
    try {
      final results = await _logDb.getRecentLogs(100);

      if (results.isNotEmpty) {
        final loadedLogs = <LogEntry>[];
        int skipped = 0;

        for (final row in results) {
          try {
            loadedLogs.add(LogEntry.fromMap(row));
          } catch (e) {
            skipped++;
            if (kDebugMode) {
              _logger.fine('跳过无法解析的日志记录: $e');
            }
          }
        }

        loadedLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _memoryLogs = loadedLogs;

        if (!_notifyScheduled) {
          _notifyScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (hasListeners) {
              notifyListeners();
            }
            _notifyScheduled = false;
          });
        }

        if (kDebugMode) {
          _logger.fine(
            '从数据库加载了 ${_memoryLogs.length} 条日志'
            '${skipped > 0 ? ", 跳过 $skipped 条损坏记录" : ""}',
          );
        }
      }
    } catch (e) {
      _logger.warning('从数据库加载日志失败: $e');
    }
  }

  /// 启动批量保存定时器
  void _startBatchSaveTimer() {
    _batchSaveTimer?.cancel();
    _batchSaveTimer = Timer.periodic(_batchSaveInterval, (_) {
      // 检查是否还有待处理的日志
      if (_pendingLogs.isEmpty) {
        return; // 没有待处理日志，跳过本次保存
      }

      // Windows平台限制批量保存的频率，避免过度写入
      if (!kIsWeb && Platform.isWindows && _pendingLogs.length < 5) {
        return; // Windows平台等待更多日志再批量保存
      }

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

    // 更新日志统计信息
    _logStats[entry.level] = (_logStats[entry.level] ?? 0) + 1;
    _lastLogTime = DateTime.now();

    // 日志性能监控
    _logOperationCount++;
    _sourceStats[entry.source ?? 'unknown'] =
        (_sourceStats[entry.source ?? 'unknown'] ?? 0) + 1;

    // 延迟通知监听器，避免在 build 方法中直接调用
    if (!_notifyScheduled) {
      _notifyScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
        _notifyScheduled = false;
      });
    }

    // 对错误级别的日志进行更积极的持久化，减少进程被杀前的丢失风险（Android常见）
    if (entry.level == UnifiedLogLevel.error) {
      // 忽略返回的 Future，避免阻塞 UI 线程
      // ignore: discarded_futures
      flushLogs();
    }
  }

  /// 将待处理的日志保存到数据库
  Future<void> _savePendingLogsToDatabase() async {
    if (_pendingLogs.isEmpty) return;

    final logsToSave = List<LogEntry>.from(_pendingLogs);
    _pendingLogs.clear();

    try {
      // 确保数据库已准备好
      await _logDb.ready;

      // 记录批量保存的统计信息
      if (kDebugMode) {
        _logger.fine('正在批量保存 ${logsToSave.length} 条日志到数据库');
      }

      await _logDb.insertLogs(logsToSave.map((log) => log.toMap()).toList());

      // 清理旧日志，但不要让清理失败影响新日志的保存
      try {
        await _logDb.deleteOldLogs(_maxStoredLogs);
      } catch (cleanupError) {
        _logger.warning('清理旧日志失败，但新日志已保存: $cleanupError');
      }

      if (kDebugMode) {
        _logger.fine('成功保存 ${logsToSave.length} 条日志到数据库');
      }
    } catch (e, stackTrace) {
      _logger.severe('保存日志到数据库失败: $e', e, stackTrace);

      // 如果保存失败，重新添加到待处理队列（但避免无限积累）
      if (_pendingLogs.length < 100) {
        _pendingLogs.addAll(logsToSave);
        _logger.warning('已将 ${logsToSave.length} 条日志重新加入待处理队列');
      } else {
        _logger.warning('待处理队列已满，丢弃 ${logsToSave.length} 条日志以防止内存溢出');
      }
    }
  }

  /// 设置新的日志级别并保存
  Future<void> setLogLevel(UnifiedLogLevel newLevel) async {
    if (_currentLevel != newLevel) {
      final oldLevel = _currentLevel;
      _currentLevel = newLevel;

      try {
        final mmkv = SafeMMKV();
        await mmkv.setInt(_logLevelKey, newLevel.index);
        // 标记用户已手动设置过日志级别，后续启动不会自动重置
        await mmkv.setBool(_logLevelUserSetKey, true);

        // 更新 logging_flutter 的级别
        _updateLoggingFlutterLevel();

        log(
          UnifiedLogLevel.info,
          '日志级别已从 ${oldLevel.name} 更改为 ${newLevel.name}',
          source: 'UnifiedLogService',
        );
      } catch (e) {
        _logger.warning('设置日志级别失败: $e');
        log(
          UnifiedLogLevel.error,
          '设置日志级别失败',
          error: e.toString(),
          source: 'UnifiedLogService',
        );
      }

      if (!_notifyScheduled) {
        _notifyScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (hasListeners) {
            notifyListeners();
          }
          _notifyScheduled = false;
        });
      }
    }
  }

  /// 清除所有内存中的日志
  void clearMemoryLogs() {
    _memoryLogs.clear();
    if (!_notifyScheduled) {
      _notifyScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
        _notifyScheduled = false;
      });
    }
    log(UnifiedLogLevel.info, '内存中的日志已清除', source: 'UnifiedLogService');
  }

  /// 清除所有存储的日志（包括数据库中的）
  Future<void> clearAllLogs() async {
    _memoryLogs.clear();
    _pendingLogs.clear();

    await _logDb.clearAllLogs();

    if (!_notifyScheduled) {
      _notifyScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
        _notifyScheduled = false;
      });
    }

    log(UnifiedLogLevel.info, '所有日志记录已清除', source: 'UnifiedLogService');
  }

  /// 查询日志（从数据库）
  Future<List<LogEntry>> queryLogs({
    UnifiedLogLevel? level,
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
      _logger.warning('查询日志失败: $e');
      return [];
    }
  }

  /// 兼容性：查询日志（返回旧格式）
  Future<List<old_log.LogEntry>> queryOldLogs({
    old_log.LogLevel? level,
    String? searchText,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    final unifiedLevel = level?.toUnifiedLogLevel;
    final results = await queryLogs(
      level: unifiedLevel,
      searchText: searchText,
      source: source,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
    );

    return results.map((e) => e.toOldLogEntry()).toList();
  }

  /// 兼容性：设置旧的日志级别
  Future<void> setOldLogLevel(old_log.LogLevel newLevel) async {
    await setLogLevel(newLevel.toUnifiedLogLevel);
  }

  /// 记录日志的方法
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // 确保已初始化
    if (!_initialized) {
      // 在初始化前将日志暂存，避免竞态导致flush时丢失
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: level,
        message: message,
        source: source,
        error: error?.toString(),
        stackTrace: stackTrace?.toString(),
      );
      _bufferDuringInit.add(entry);
      // 触发初始化（若尚未开始）
      // ignore: discarded_futures
      _initialize();
      return;
    }

    // 防止递归
    if (_isLogging) return;

    // 只有当消息的级别大于或等于当前设置的级别时才记录
    if (level.index >= _currentLevel.index &&
        _currentLevel != UnifiedLogLevel.none) {
      _isLogging = true;
      try {
        // 直接添加到我们的日志系统，不通过 logging_flutter 避免递归
        _addLogEntry(
          LogEntry(
            timestamp: DateTime.now(),
            level: level,
            message: message,
            source: source,
            error: error?.toString(),
            stackTrace: stackTrace?.toString(),
          ),
        );

        // 同时使用 logging_flutter 记录日志（仅用于控制台输出）
        if (kDebugMode) {
          final loggingLevel = _mapUnifiedLevelToLogging(level);
          final loggerName = source ?? 'ThoughtEcho';
          final logger = logging.Logger(loggerName);

          logger.log(loggingLevel, message, error, stackTrace);
        }
      } finally {
        _isLogging = false;
      }
    }
  }

  /// 立即刷新所有待处理的日志到数据库
  Future<void> flushLogs() async {
    // 等待初始化完成，确保预初始化期间缓存的日志被转移
    if (_initCompleter != null && !(_initCompleter!.isCompleted)) {
      await _initCompleter!.future;
    }
    // 将初始化前的缓存也加入待持久化
    if (_bufferDuringInit.isNotEmpty) {
      for (final e in List<LogEntry>.from(_bufferDuringInit)) {
        _addLogEntry(e);
      }
      _bufferDuringInit.clear();
    }
    if (_pendingLogs.isNotEmpty) {
      await _savePendingLogsToDatabase();
    }
  }

  /// 销毁时释放资源
  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _batchSaveTimer?.cancel();
    // 虽然 dispose 不能等待，但仍尽量触发一次持久化
    // 忽略等待，防止阻塞销毁流程
    // ignore: discarded_futures
    _savePendingLogsToDatabase();
    super.dispose();
  }

  /// 监听应用生命周期变化，在进入后台或分离时刷新待写入日志
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // 主动持久化，避免在 Android 等平台上因进程被杀导致日志丢失
        // ignore: discarded_futures
        _savePendingLogsToDatabase();
        break;
      case AppLifecycleState.resumed:
        // 无需处理
        break;
    }
  }

  // 提供便捷的日志记录方法
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.verbose,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.debug,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.info,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.warning,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.error,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  /// 获取日志统计摘要
  Map<String, dynamic> getLogSummary() {
    return {
      'totalLogs': _memoryLogs.length,
      'pendingLogs': _pendingLogs.length,
      'currentLevel': _currentLevel.name,
      'lastLogTime': _lastLogTime?.toIso8601String(),
      'logStats': _logStats.map((k, v) => MapEntry(k.name, v)),
      'initialized': _initialized,
    };
  }

  /// 获取数据库状态信息（用于调试）
  Future<Map<String, dynamic>> getDatabaseStatus() async {
    try {
      return await _logDb.getDatabaseStatus();
    } catch (e) {
      return {'error': e.toString(), 'initialized': _initialized};
    }
  }

  /// 重置日志统计信息
  void resetLogStats() {
    _logStats.clear();
    _lastLogTime = null;
    log(UnifiedLogLevel.info, '日志统计信息已重置', source: 'UnifiedLogService');
  }

  /// 导出日志为文本格式
  String exportLogsAsText({
    UnifiedLogLevel? minLevel,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# ThoughtEcho 日志导出');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('日志级别: ${minLevel?.name ?? '所有级别'}');
    buffer.writeln('');

    final filteredLogs = _memoryLogs.where((log) {
      if (minLevel != null && log.level.index < minLevel.index) return false;
      if (startDate != null && log.timestamp.isBefore(startDate)) return false;
      if (endDate != null && log.timestamp.isAfter(endDate)) return false;
      return true;
    });

    for (final log in filteredLogs) {
      buffer.writeln(log.toString());
      buffer.writeln('---');
    }

    return buffer.toString();
  }

  /// 处理在日志服务初始化之前缓存的错误
  Future<void> _processDeferredErrors() async {
    try {
      const Function getAndClearDeferredErrorsFunc = getAndClearDeferredErrors;
      final errorsList = getAndClearDeferredErrorsFunc();

      if (errorsList.isNotEmpty) {
        for (final errorMap in errorsList) {
          log(
            UnifiedLogLevel.error,
            errorMap['message'] as String? ?? '未知错误',
            error: errorMap['error'],
            stackTrace: errorMap['stackTrace'] != null
                ? StackTrace.fromString(errorMap['stackTrace'].toString())
                : null,
            source: errorMap['source'] as String? ?? 'unknown',
          );
        }
        _logger.info('处理了 ${errorsList.length} 条早期缓存错误');
      }
    } catch (e) {
      _logger.warning('处理缓存错误时出错: $e');
    }
  }

  /// 注册全局异常处理
  void registerGlobalErrorHandlers() {
    if (!kIsWeb && !Platform.isIOS && !Platform.isAndroid) {
      _logger.info('已为桌面平台注册全局异常处理');
    }
  }

  /// 获取日志性能统计
  Map<String, dynamic> getPerformanceStats() {
    return {
      'logOperationCount': _logOperationCount,
      'averageLogsPerMinute': _calculateLogsPerMinute(),
      'topSources': _getTopLogSources(),
      'lastPerformanceReset': _lastPerformanceReset?.toIso8601String(),
      'memoryUsage': '${_memoryLogs.length}/$_maxInMemoryLogs',
      'pendingLogs': _pendingLogs.length,
    };
  }

  /// 计算每分钟日志数
  double _calculateLogsPerMinute() {
    if (_lastPerformanceReset == null || _logOperationCount == 0) return 0.0;

    final duration = DateTime.now().difference(_lastPerformanceReset!);
    final minutes = duration.inMinutes;

    return minutes > 0
        ? _logOperationCount / minutes
        : _logOperationCount.toDouble();
  }

  /// 获取排名前5的日志来源
  List<Map<String, dynamic>> _getTopLogSources() {
    final entries = _sourceStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries
        .take(5)
        .map((e) => {'source': e.key, 'count': e.value})
        .toList();
  }

  /// 重置性能统计
  void resetPerformanceStats() {
    _logOperationCount = 0;
    _lastPerformanceReset = DateTime.now();
    _sourceStats.clear();
    log(UnifiedLogLevel.info, '日志性能统计已重置', source: 'UnifiedLogService');
  }
}
