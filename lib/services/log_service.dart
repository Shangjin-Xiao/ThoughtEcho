import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  LogLevel get currentLevel => _currentLevel;

  LogService() {
    _loadLogLevel();
  }

  // 从 SharedPreferences 加载日志级别
  Future<void> _loadLogLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final levelIndex = prefs.getInt(_logLevelKey) ?? LogLevel.info.index;
    // 确保索引在有效范围内
    if (levelIndex >= 0 && levelIndex < LogLevel.values.length) {
       _currentLevel = LogLevel.values[levelIndex];
    } else {
       _currentLevel = LogLevel.info; // 默认值
       await prefs.setInt(_logLevelKey, _currentLevel.index); // 保存默认值
    }
    notifyListeners();
    // 应用启动时打印一次当前日志级别
    log(LogLevel.info, 'Log level initialized to: ${_currentLevel.name}');
  }

  // 设置新的日志级别并保存
  Future<void> setLogLevel(LogLevel newLevel) async {
    if (_currentLevel != newLevel) {
      _currentLevel = newLevel;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_logLevelKey, newLevel.index);
      log(LogLevel.info, 'Log level changed to: ${_currentLevel.name}');
      notifyListeners();
    }
  }

  // 记录日志的方法
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    // 只有当消息的级别大于或等于当前设置的级别时才记录
    if (level.index >= _currentLevel.index && _currentLevel != LogLevel.none) {
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
      // TODO: 未来可以实现将日志写入文件或其他存储
    }
  }

  // 提供便捷的日志记录方法
  void verbose(String message) => log(LogLevel.verbose, message);
  void debug(String message) => log(LogLevel.debug, message);
  void info(String message) => log(LogLevel.info, message);
  void warning(String message, {Object? error}) => log(LogLevel.warning, message, error: error);
  void error(String message, {Object? error, StackTrace? stackTrace}) => log(LogLevel.error, message, error: error, stackTrace: stackTrace);
}
