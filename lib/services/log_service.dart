import 'package:flutter/foundation.dart';
import 'package:mind_trace/utils/mmkv_ffi_fix.dart'; // 导入 SafeMMKV

// 定义日志级别
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  none, // 不记录任何日志
}

class LogService with ChangeNotifier {
  static const String _logLevelKey = 'log_level';
  LogLevel _currentLevel = LogLevel.info; // 默认级别
  bool _initialized = false;
  
  // 存储日志记录
  List<String> _logs = [];
  List<String> get logs => _logs;

  LogLevel get currentLevel => _currentLevel;

  LogService() {
    _initialize();
  }

  // 初始化日志服务
  Future<void> _initialize() async {
    if (_initialized) return;
    
    try {
      // 初始化 SafeMMKV
      final mmkv = SafeMMKV();
      await mmkv.initialize();
      
      await _loadLogLevel();
      _initialized = true;
      
      // 添加一条日志表示服务已启动
      log(LogLevel.info, '日志服务已启动');
    } catch (e, stack) {
      debugPrint('日志服务初始化失败: $e');
      debugPrint('$stack');
      // 初始化失败也设置为已初始化，避免重复尝试
      _initialized = true;
      _currentLevel = LogLevel.info;
      
      // 记录错误但不会导致递归（因为我们直接使用 debugPrint）
      final timestamp = DateTime.now().toIso8601String();
      _logs.add('$timestamp [ERROR] 日志服务初始化失败: $e');
      notifyListeners();
    }
  }

  // 从 SafeMMKV 加载日志级别
  Future<void> _loadLogLevel() async {
    final mmkv = SafeMMKV();
    final levelIndex = mmkv.getInt(_logLevelKey) ?? LogLevel.info.index;
    
    // 确保索引在有效范围内
    if (levelIndex >= 0 && levelIndex < LogLevel.values.length) {
      _currentLevel = LogLevel.values[levelIndex];
    } else {
      _currentLevel = LogLevel.info; // 默认值
      await mmkv.setInt(_logLevelKey, _currentLevel.index); // 保存默认值
    }
    
    notifyListeners();
    
    // 应用启动时打印一次当前日志级别
    // 使用 _logInternal 避免在初始化阶段递归调用 log 方法
    _logInternal(LogLevel.info, '日志级别已初始化为: ${_currentLevel.name}');
  }

  // 设置新的日志级别并保存
  Future<void> setLogLevel(LogLevel newLevel) async {
    if (_currentLevel != newLevel) {
      _currentLevel = newLevel;
      try {
        final mmkv = SafeMMKV();
        await mmkv.setInt(_logLevelKey, newLevel.index);
        log(LogLevel.info, '日志级别已更改为: ${_currentLevel.name}');
      } catch (e) {
        debugPrint('设置日志级别失败: $e');
        log(LogLevel.error, '设置日志级别失败', error: e);
      }
      notifyListeners();
    }
  }
  
  // 清除所有存储的日志
  void clearLogs() {
    _logs.clear();
    notifyListeners();
    log(LogLevel.info, '日志已清除');
  }

  // 内部使用的日志记录方法，避免递归
  void _logInternal(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    if (_currentLevel == LogLevel.none) return;
    
    final timestamp = DateTime.now().toIso8601String();
    String logMessage = '$timestamp [${level.name.toUpperCase()}] $message';
    
    if (error != null) {
      logMessage += '\nError: $error';
    }
    if (stackTrace != null) {
      logMessage += '\nStackTrace: $stackTrace';
    }
    
    // 在Debug模式下打印到控制台
    if (kDebugMode) {
      print(logMessage);
    }
    
    // 保存日志到内存中，限制日志数量防止内存占用过大
    _logs.add(logMessage);
    if (_logs.length > 1000) {
      _logs.removeAt(0); // 移除最早的日志
    }
  }

  // 记录日志的方法
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    // 确保已初始化
    if (!_initialized) {
      // 加入队列，待初始化完成后处理
      _initialize().then((_) {
        log(level, message, error: error, stackTrace: stackTrace);
      });
      return;
    }
    
    // 只有当消息的级别大于或等于当前设置的级别时才记录
    if (level.index >= _currentLevel.index && _currentLevel != LogLevel.none) {
      _logInternal(level, message, error: error, stackTrace: stackTrace);
      
      // 所有级别的日志都通知监听器，确保 UI 更新
      notifyListeners();
    }
  }

  // 提供便捷的日志记录方法
  void verbose(String message) => log(LogLevel.verbose, message);
  void debug(String message) => log(LogLevel.debug, message);
  void info(String message) => log(LogLevel.info, message);
  void warning(String message, {Object? error}) => log(LogLevel.warning, message, error: error);
  void error(String message, {Object? error, StackTrace? stackTrace}) => 
      log(LogLevel.error, message, error: error, stackTrace: stackTrace);
}
