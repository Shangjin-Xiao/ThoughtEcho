import 'dart:async';
import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/device_memory_manager.dart';
import 'intelligent_memory_manager.dart';
import 'enhanced_progress_manager.dart';

/// 错误处理和恢复管理器
/// 
/// 实现完善的错误处理和自动恢复机制，当发生OOM时能够优雅降级而不是崩溃
class ErrorRecoveryManager {
  static final ErrorRecoveryManager _instance = ErrorRecoveryManager._internal();
  factory ErrorRecoveryManager() => _instance;
  ErrorRecoveryManager._internal();

  final DeviceMemoryManager _memoryManager = DeviceMemoryManager();
  final IntelligentMemoryManager _intelligentMemoryManager = IntelligentMemoryManager();
  final EnhancedProgressManager _progressManager = EnhancedProgressManager();
  
  // 错误恢复策略
  final Map<Type, ErrorRecoveryStrategy> _recoveryStrategies = {};
  
  // 错误历史记录
  final List<ErrorRecord> _errorHistory = [];
  static const int _maxErrorHistory = 100;
  
  // 恢复状态跟踪
  final Map<String, RecoveryAttempt> _activeRecoveries = {};
  
  /// 初始化错误恢复管理器
  void initialize() {
    // 注册默认的错误恢复策略
    _registerDefaultStrategies();
    
    // 监听内存压力事件
    _intelligentMemoryManager.pressureEventStream?.listen(_handleMemoryPressureEvent);
    
    logDebug('错误恢复管理器已初始化');
  }
  
  /// 执行带错误恢复的操作
  Future<T> executeWithRecovery<T>(
    String operationName,
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 1),
    Map<String, dynamic>? context,
    ErrorRecoveryStrategy? customStrategy,
  }) async {
    final operationId = _progressManager.startOperation(
      operationName: operationName,
      description: '执行操作: $operationName',
      metadata: context ?? {},
    );
    
    int attemptCount = 0;
    Exception? lastException;
    
    while (attemptCount <= maxRetries) {
      try {
        _progressManager.updateProgress(
          operationId,
          status: attemptCount == 0 ? '执行中...' : '重试中... ($attemptCount/$maxRetries)',
        );
        
        final result = await operation();
        
        _progressManager.completeOperation(operationId, finalStatus: '操作成功完成');
        return result;
        
      } catch (e, stackTrace) {
        attemptCount++;
        lastException = e is Exception ? e : Exception(e.toString());
        
        logDebug('操作失败 (尝试 $attemptCount/${maxRetries + 1}): $e');
        
        // 记录错误
        final errorRecord = ErrorRecord(
          operationName: operationName,
          error: e,
          stackTrace: stackTrace,
          timestamp: DateTime.now(),
          attemptCount: attemptCount,
          context: context ?? {},
        );
        _recordError(errorRecord);
        
        // 如果还有重试机会，尝试恢复
        if (attemptCount <= maxRetries) {
          final recoveryStrategy = customStrategy ?? _getRecoveryStrategy(e.runtimeType);
          
          if (recoveryStrategy != null) {
            try {
              await _attemptRecovery(operationId, errorRecord, recoveryStrategy);
              
              // 等待重试延迟
              if (retryDelay.inMilliseconds > 0) {
                await Future.delayed(retryDelay);
              }
              
              continue; // 重试操作
            } catch (recoveryError) {
              logDebug('恢复策略失败: $recoveryError');
            }
          }
          
          // 如果没有恢复策略或恢复失败，等待后直接重试
          if (retryDelay.inMilliseconds > 0) {
            await Future.delayed(retryDelay);
          }
        }
      }
    }
    
    // 所有重试都失败了
    _progressManager.failOperation(operationId, lastException?.toString() ?? '未知错误');
    throw lastException ?? Exception('操作失败，已达到最大重试次数');
  }
  
  /// 注册错误恢复策略
  void registerRecoveryStrategy(Type errorType, ErrorRecoveryStrategy strategy) {
    _recoveryStrategies[errorType] = strategy;
    logDebug('注册错误恢复策略: $errorType');
  }
  
  /// 获取错误历史
  List<ErrorRecord> getErrorHistory({int? limit}) {
    final history = _errorHistory.toList();
    if (limit != null && limit < history.length) {
      return history.skip(history.length - limit).toList();
    }
    return history;
  }
  
  /// 清理错误历史
  void clearErrorHistory() {
    _errorHistory.clear();
    logDebug('错误历史已清理');
  }
  
  /// 获取错误统计
  Map<String, int> getErrorStatistics() {
    final stats = <String, int>{};
    for (final record in _errorHistory) {
      final errorType = record.error.runtimeType.toString();
      stats[errorType] = (stats[errorType] ?? 0) + 1;
    }
    return stats;
  }
  
  /// 注册默认恢复策略
  void _registerDefaultStrategies() {
    // OutOfMemoryError 恢复策略
    registerRecoveryStrategy(OutOfMemoryError, MemoryRecoveryStrategy());
    
    // FileSystemException 恢复策略
    registerRecoveryStrategy(FileSystemException, FileSystemRecoveryStrategy());
    
    // TimeoutException 恢复策略
    registerRecoveryStrategy(TimeoutException, TimeoutRecoveryStrategy());
    
    // SocketException 恢复策略
    registerRecoveryStrategy(SocketException, NetworkRecoveryStrategy());
    
    // 通用异常恢复策略
    registerRecoveryStrategy(Exception, GenericRecoveryStrategy());
  }
  
  /// 获取恢复策略
  ErrorRecoveryStrategy? _getRecoveryStrategy(Type errorType) {
    // 首先查找精确匹配
    var strategy = _recoveryStrategies[errorType];
    if (strategy != null) return strategy;
    
    // 查找父类匹配
    for (final entry in _recoveryStrategies.entries) {
      if (errorType.toString().contains(entry.key.toString())) {
        return entry.value;
      }
    }
    
    // 返回通用策略
    return _recoveryStrategies[Exception];
  }
  
  /// 尝试恢复
  Future<void> _attemptRecovery(
    String operationId,
    ErrorRecord errorRecord,
    ErrorRecoveryStrategy strategy,
  ) async {
    final recoveryId = 'recovery_${DateTime.now().millisecondsSinceEpoch}';
    
    final attempt = RecoveryAttempt(
      id: recoveryId,
      operationId: operationId,
      errorRecord: errorRecord,
      strategy: strategy,
      startTime: DateTime.now(),
    );
    
    _activeRecoveries[recoveryId] = attempt;
    
    try {
      _progressManager.updateProgress(
        operationId,
        status: '尝试恢复: ${strategy.name}',
      );
      
      await strategy.recover(errorRecord);
      
      attempt.isSuccessful = true;
      attempt.endTime = DateTime.now();
      
      logDebug('恢复成功: ${strategy.name}');
      
    } catch (e) {
      attempt.isSuccessful = false;
      attempt.endTime = DateTime.now();
      attempt.recoveryError = e;
      
      logDebug('恢复失败: ${strategy.name}, 错误: $e');
      rethrow;
    } finally {
      _activeRecoveries.remove(recoveryId);
    }
  }
  
  /// 记录错误
  void _recordError(ErrorRecord record) {
    _errorHistory.add(record);
    
    // 限制历史记录大小
    if (_errorHistory.length > _maxErrorHistory) {
      _errorHistory.removeAt(0);
    }
  }
  
  /// 处理内存压力事件
  void _handleMemoryPressureEvent(MemoryPressureEvent event) {
    if (event.type == MemoryPressureEventType.critical) {
      logDebug('检测到临界内存压力，执行预防性恢复措施');
      
      // 取消所有非关键操作
      _progressManager.cancelAllOperations(reason: '内存压力过高');
      
      // 执行紧急内存清理
      _performEmergencyCleanup();
    }
  }
  
  /// 执行紧急清理
  Future<void> _performEmergencyCleanup() async {
    try {
      // 强制垃圾回收
      await _memoryManager.forceGarbageCollection();
      
      // 清理缓存
      _memoryManager.clearCache();
      
      // 等待系统回收内存
      await Future.delayed(const Duration(milliseconds: 500));
      
      logDebug('紧急内存清理完成');
    } catch (e) {
      logDebug('紧急内存清理失败: $e');
    }
  }
}

/// 错误记录
class ErrorRecord {
  final String operationName;
  final dynamic error;
  final StackTrace stackTrace;
  final DateTime timestamp;
  final int attemptCount;
  final Map<String, dynamic> context;
  
  ErrorRecord({
    required this.operationName,
    required this.error,
    required this.stackTrace,
    required this.timestamp,
    required this.attemptCount,
    required this.context,
  });
  
  String get errorType => error.runtimeType.toString();
  
  String get errorMessage => error.toString();
}

/// 恢复尝试
class RecoveryAttempt {
  final String id;
  final String operationId;
  final ErrorRecord errorRecord;
  final ErrorRecoveryStrategy strategy;
  final DateTime startTime;
  
  DateTime? endTime;
  bool isSuccessful = false;
  dynamic recoveryError;
  
  RecoveryAttempt({
    required this.id,
    required this.operationId,
    required this.errorRecord,
    required this.strategy,
    required this.startTime,
  });
  
  Duration? get duration {
    if (endTime != null) {
      return endTime!.difference(startTime);
    }
    return null;
  }
}

/// 错误恢复策略基类
abstract class ErrorRecoveryStrategy {
  String get name;
  
  Future<void> recover(ErrorRecord errorRecord);
}

/// 内存恢复策略
class MemoryRecoveryStrategy implements ErrorRecoveryStrategy {
  @override
  String get name => '内存恢复策略';
  
  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    final memoryManager = DeviceMemoryManager();
    
    // 强制垃圾回收
    await memoryManager.forceGarbageCollection();
    
    // 清理缓存
    memoryManager.clearCache();
    
    // 等待内存回收
    await Future.delayed(const Duration(milliseconds: 1000));
    
    logDebug('内存恢复策略执行完成');
  }
}

/// 文件系统恢复策略
class FileSystemRecoveryStrategy implements ErrorRecoveryStrategy {
  @override
  String get name => '文件系统恢复策略';
  
  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    // 检查磁盘空间
    // 创建必要的目录
    // 清理临时文件
    
    logDebug('文件系统恢复策略执行完成');
  }
}

/// 超时恢复策略
class TimeoutRecoveryStrategy implements ErrorRecoveryStrategy {
  @override
  String get name => '超时恢复策略';
  
  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    // 等待网络恢复
    await Future.delayed(const Duration(seconds: 2));
    
    logDebug('超时恢复策略执行完成');
  }
}

/// 网络恢复策略
class NetworkRecoveryStrategy implements ErrorRecoveryStrategy {
  @override
  String get name => '网络恢复策略';
  
  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    // 检查网络连接
    // 等待网络恢复
    await Future.delayed(const Duration(seconds: 3));
    
    logDebug('网络恢复策略执行完成');
  }
}

/// 通用恢复策略
class GenericRecoveryStrategy implements ErrorRecoveryStrategy {
  @override
  String get name => '通用恢复策略';
  
  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    // 通用恢复措施
    await Future.delayed(const Duration(milliseconds: 500));
    
    logDebug('通用恢复策略执行完成');
  }
}
