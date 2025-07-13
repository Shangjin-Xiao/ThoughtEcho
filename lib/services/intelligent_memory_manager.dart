import 'dart:async';
import '../utils/device_memory_manager.dart';
import '../utils/app_logger.dart';

/// 智能内存压力管理器
/// 
/// 提供智能的内存压力检测和响应系统，根据设备状态动态调整处理策略
class IntelligentMemoryManager {
  static final IntelligentMemoryManager _instance = IntelligentMemoryManager._internal();
  factory IntelligentMemoryManager() => _instance;
  IntelligentMemoryManager._internal();

  final DeviceMemoryManager _deviceMemoryManager = DeviceMemoryManager();
  
  // 内存监控状态
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  StreamController<MemoryPressureEvent>? _pressureEventController;
  
  // 内存压力历史记录
  final List<MemoryPressureRecord> _pressureHistory = [];
  static const int _maxHistorySize = 100;
  
  // 自适应策略配置
  final Map<String, AdaptiveStrategy> _strategies = {};
  
  /// 开始智能内存监控
  Future<void> startIntelligentMonitoring({
    Duration interval = const Duration(seconds: 3),
  }) async {
    if (_isMonitoring) {
      return;
    }
    
    _isMonitoring = true;
    _pressureEventController = StreamController<MemoryPressureEvent>.broadcast();
    
    logDebug('开始智能内存监控');
    
    // 启动原生内存监控
    await _deviceMemoryManager.startMemoryMonitoring(intervalMs: interval.inMilliseconds);
    
    // 启动智能分析定时器
    _monitoringTimer = Timer.periodic(interval, (_) => _analyzeMemoryPressure());
    
    // 监听原生内存状态更新
    _deviceMemoryManager.memoryStatusStream?.listen((data) {
      _handleNativeMemoryUpdate(data);
    });
  }
  
  /// 停止智能内存监控
  Future<void> stopIntelligentMonitoring() async {
    if (!_isMonitoring) {
      return;
    }
    
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    await _deviceMemoryManager.stopMemoryMonitoring();
    await _pressureEventController?.close();
    _pressureEventController = null;
    
    logDebug('智能内存监控已停止');
  }
  
  /// 获取内存压力事件流
  Stream<MemoryPressureEvent>? get pressureEventStream => _pressureEventController?.stream;
  
  /// 注册自适应策略
  void registerStrategy(String operationName, AdaptiveStrategy strategy) {
    _strategies[operationName] = strategy;
    logDebug('注册自适应策略: $operationName');
  }
  
  /// 获取操作的最佳策略
  Future<OperationStrategy> getOptimalStrategy(String operationName, {
    int? dataSize,
    Map<String, dynamic>? context,
  }) async {
    final strategy = _strategies[operationName];
    if (strategy == null) {
      return OperationStrategy.defaultStrategy();
    }
    
    final memoryPressure = await _deviceMemoryManager.getMemoryPressureLevel();
    final availableMemory = await _deviceMemoryManager.getAvailableMemory();
    
    final memoryContext = MemoryContext(
      pressureLevel: memoryPressure,
      availableMemory: availableMemory,
      dataSize: dataSize,
      operationName: operationName,
      additionalContext: context ?? {},
    );
    
    return strategy.getStrategy(memoryContext);
  }
  
  /// 执行内存安全的操作
  Future<T> executeWithAdaptiveStrategy<T>(
    String operationName,
    Future<T> Function(OperationStrategy strategy) operation, {
    int? dataSize,
    Map<String, dynamic>? context,
  }) async {
    final strategy = await getOptimalStrategy(
      operationName,
      dataSize: dataSize,
      context: context,
    );
    
    logDebug('执行操作 $operationName，策略: ${strategy.description}');
    
    try {
      // 执行前检查内存压力
      await _preExecutionCheck(strategy);
      
      // 执行操作
      final result = await operation(strategy);
      
      // 执行后清理
      await _postExecutionCleanup(strategy);
      
      return result;
    } catch (e) {
      logDebug('操作 $operationName 执行失败: $e');
      
      // 如果是内存相关错误，尝试降级策略
      if (_isMemoryRelatedError(e)) {
        final fallbackStrategy = strategy.getFallbackStrategy();
        if (fallbackStrategy != null) {
          logDebug('尝试降级策略: ${fallbackStrategy.description}');
          return await operation(fallbackStrategy);
        }
      }
      
      rethrow;
    }
  }
  
  /// 分析内存压力趋势
  Future<void> _analyzeMemoryPressure() async {
    try {
      final memoryPressure = await _deviceMemoryManager.getMemoryPressureLevel();
      final availableMemory = await _deviceMemoryManager.getAvailableMemory();
      final timestamp = DateTime.now();
      
      // 记录压力历史
      final record = MemoryPressureRecord(
        timestamp: timestamp,
        pressureLevel: memoryPressure,
        availableMemory: availableMemory,
      );
      
      _pressureHistory.add(record);
      if (_pressureHistory.length > _maxHistorySize) {
        _pressureHistory.removeAt(0);
      }
      
      // 分析趋势
      final trend = _analyzePressureTrend();
      
      // 如果检测到压力上升趋势，发出预警
      if (trend == PressureTrend.rising && memoryPressure >= 2) {
        _emitPressureEvent(MemoryPressureEvent(
          type: MemoryPressureEventType.warning,
          currentPressure: memoryPressure,
          trend: trend,
          message: '检测到内存压力上升趋势',
          timestamp: timestamp,
        ));
      }
      
      // 如果压力达到临界状态，发出紧急事件
      if (memoryPressure >= 3) {
        _emitPressureEvent(MemoryPressureEvent(
          type: MemoryPressureEventType.critical,
          currentPressure: memoryPressure,
          trend: trend,
          message: '内存压力达到临界状态',
          timestamp: timestamp,
        ));
        
        // 执行紧急内存清理
        await _emergencyMemoryCleanup();
      }
    } catch (e) {
      logDebug('分析内存压力失败: $e');
    }
  }
  
  /// 处理原生内存更新
  void _handleNativeMemoryUpdate(Map<String, dynamic> data) {
    final pressureLevel = data['pressureLevel'] as int? ?? 0;

    // 可以在这里添加更详细的原生内存数据处理逻辑
    logDebug('收到原生内存更新: 压力级别=$pressureLevel');
  }
  
  /// 分析压力趋势
  PressureTrend _analyzePressureTrend() {
    if (_pressureHistory.length < 3) {
      return PressureTrend.stable;
    }
    
    final recent = _pressureHistory.length >= 5
        ? _pressureHistory.skip(_pressureHistory.length - 5).toList()
        : _pressureHistory.toList();
    final avgRecent = recent.map((r) => r.pressureLevel).reduce((a, b) => a + b) / recent.length;

    final older = _pressureHistory.length >= 10
        ? _pressureHistory.skip(_pressureHistory.length - 10).take(5).toList()
        : [];
    if (older.isEmpty) {
      return PressureTrend.stable;
    }
    
    final avgOlder = older.map((r) => r.pressureLevel).reduce((a, b) => a + b) / older.length;
    
    if (avgRecent > avgOlder + 0.5) {
      return PressureTrend.rising;
    } else if (avgRecent < avgOlder - 0.5) {
      return PressureTrend.falling;
    } else {
      return PressureTrend.stable;
    }
  }
  
  /// 发出压力事件
  void _emitPressureEvent(MemoryPressureEvent event) {
    _pressureEventController?.add(event);
  }
  
  /// 执行前检查
  Future<void> _preExecutionCheck(OperationStrategy strategy) async {
    if (strategy.requiresMemoryCheck) {
      final memoryPressure = await _deviceMemoryManager.getMemoryPressureLevel();
      if (memoryPressure >= 3) {
        throw MemoryPressureException('内存压力过高，无法执行操作');
      }
    }
  }
  
  /// 执行后清理
  Future<void> _postExecutionCleanup(OperationStrategy strategy) async {
    if (strategy.requiresCleanup) {
      await _deviceMemoryManager.forceGarbageCollection();
    }
  }
  
  /// 紧急内存清理
  Future<void> _emergencyMemoryCleanup() async {
    logDebug('执行紧急内存清理');
    
    // 强制垃圾回收
    await _deviceMemoryManager.forceGarbageCollection();
    
    // 清理内存缓存
    _deviceMemoryManager.clearCache();
    
    // 等待一段时间让系统回收内存
    await Future.delayed(const Duration(milliseconds: 500));
  }
  
  /// 检查是否为内存相关错误
  bool _isMemoryRelatedError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('memory') || 
           errorString.contains('oom') || 
           errorString.contains('内存');
  }
}

/// 内存压力记录
class MemoryPressureRecord {
  final DateTime timestamp;
  final int pressureLevel;
  final int availableMemory;
  
  MemoryPressureRecord({
    required this.timestamp,
    required this.pressureLevel,
    required this.availableMemory,
  });
}

/// 压力趋势
enum PressureTrend {
  rising,   // 上升
  falling,  // 下降
  stable,   // 稳定
}

/// 内存压力事件类型
enum MemoryPressureEventType {
  info,     // 信息
  warning,  // 警告
  critical, // 临界
}

/// 内存压力事件
class MemoryPressureEvent {
  final MemoryPressureEventType type;
  final int currentPressure;
  final PressureTrend trend;
  final String message;
  final DateTime timestamp;
  
  MemoryPressureEvent({
    required this.type,
    required this.currentPressure,
    required this.trend,
    required this.message,
    required this.timestamp,
  });
}

/// 内存压力异常
class MemoryPressureException implements Exception {
  final String message;

  MemoryPressureException(this.message);

  @override
  String toString() => 'MemoryPressureException: $message';
}

/// 内存上下文
class MemoryContext {
  final int pressureLevel;
  final int availableMemory;
  final int? dataSize;
  final String operationName;
  final Map<String, dynamic> additionalContext;

  MemoryContext({
    required this.pressureLevel,
    required this.availableMemory,
    this.dataSize,
    required this.operationName,
    required this.additionalContext,
  });

  /// 获取内存使用率
  double get memoryUsageRatio {
    // 这里需要根据实际的总内存来计算
    // 暂时使用一个估算值
    const totalMemory = 4 * 1024 * 1024 * 1024; // 假设4GB
    return 1.0 - (availableMemory / totalMemory);
  }

  /// 是否为高内存压力
  bool get isHighPressure => pressureLevel >= 2;

  /// 是否为临界内存压力
  bool get isCriticalPressure => pressureLevel >= 3;
}

/// 操作策略
class OperationStrategy {
  final String name;
  final String description;
  final int chunkSize;
  final bool useIsolate;
  final bool useStreaming;
  final bool requiresMemoryCheck;
  final bool requiresCleanup;
  final int maxRetries;
  final Duration timeout;
  final OperationStrategy? fallbackStrategy;

  OperationStrategy({
    required this.name,
    required this.description,
    this.chunkSize = 64 * 1024,
    this.useIsolate = false,
    this.useStreaming = false,
    this.requiresMemoryCheck = true,
    this.requiresCleanup = false,
    this.maxRetries = 1,
    this.timeout = const Duration(minutes: 5),
    this.fallbackStrategy,
  });

  /// 默认策略
  factory OperationStrategy.defaultStrategy() {
    return OperationStrategy(
      name: 'default',
      description: '默认策略',
    );
  }

  /// 高性能策略
  factory OperationStrategy.highPerformance() {
    return OperationStrategy(
      name: 'high_performance',
      description: '高性能策略',
      chunkSize: 1024 * 1024, // 1MB
      useIsolate: true,
      requiresCleanup: true,
    );
  }

  /// 内存保守策略
  factory OperationStrategy.memoryConservative() {
    return OperationStrategy(
      name: 'memory_conservative',
      description: '内存保守策略',
      chunkSize: 16 * 1024, // 16KB
      useStreaming: true,
      requiresMemoryCheck: true,
      requiresCleanup: true,
      maxRetries: 0,
    );
  }

  /// 最小化策略
  factory OperationStrategy.minimal() {
    return OperationStrategy(
      name: 'minimal',
      description: '最小化策略',
      chunkSize: 4 * 1024, // 4KB
      useStreaming: true,
      requiresMemoryCheck: true,
      requiresCleanup: true,
      maxRetries: 0,
      timeout: const Duration(minutes: 10),
    );
  }

  /// 获取降级策略
  OperationStrategy? getFallbackStrategy() {
    return fallbackStrategy;
  }
}

/// 自适应策略
abstract class AdaptiveStrategy {
  /// 根据内存上下文获取最佳策略
  OperationStrategy getStrategy(MemoryContext context);
}

/// 文件处理自适应策略
class FileProcessingAdaptiveStrategy implements AdaptiveStrategy {
  @override
  OperationStrategy getStrategy(MemoryContext context) {
    final dataSize = context.dataSize ?? 0;

    // 临界内存压力
    if (context.isCriticalPressure) {
      return OperationStrategy.minimal().copyWith(
        fallbackStrategy: null, // 最后的策略，没有降级选项
      );
    }

    // 高内存压力
    if (context.isHighPressure) {
      return OperationStrategy.memoryConservative().copyWith(
        fallbackStrategy: OperationStrategy.minimal(),
      );
    }

    // 大文件处理
    if (dataSize > 100 * 1024 * 1024) { // 100MB以上
      return OperationStrategy.memoryConservative().copyWith(
        fallbackStrategy: OperationStrategy.minimal(),
      );
    }

    // 中等文件处理
    if (dataSize > 10 * 1024 * 1024) { // 10MB以上
      return OperationStrategy.defaultStrategy().copyWith(
        fallbackStrategy: OperationStrategy.memoryConservative(),
      );
    }

    // 小文件或正常内存压力
    return OperationStrategy.highPerformance().copyWith(
      fallbackStrategy: OperationStrategy.defaultStrategy(),
    );
  }
}

/// 备份还原自适应策略
class BackupRestoreAdaptiveStrategy implements AdaptiveStrategy {
  @override
  OperationStrategy getStrategy(MemoryContext context) {
    // 备份还原总是使用保守策略
    if (context.isCriticalPressure) {
      return OperationStrategy.minimal();
    }

    if (context.isHighPressure) {
      return OperationStrategy.memoryConservative().copyWith(
        fallbackStrategy: OperationStrategy.minimal(),
      );
    }

    return OperationStrategy.memoryConservative().copyWith(
      chunkSize: 32 * 1024, // 32KB
      fallbackStrategy: OperationStrategy.minimal(),
    );
  }
}

/// 操作策略扩展
extension OperationStrategyExtension on OperationStrategy {
  /// 复制策略并修改部分属性
  OperationStrategy copyWith({
    String? name,
    String? description,
    int? chunkSize,
    bool? useIsolate,
    bool? useStreaming,
    bool? requiresMemoryCheck,
    bool? requiresCleanup,
    int? maxRetries,
    Duration? timeout,
    OperationStrategy? fallbackStrategy,
  }) {
    return OperationStrategy(
      name: name ?? this.name,
      description: description ?? this.description,
      chunkSize: chunkSize ?? this.chunkSize,
      useIsolate: useIsolate ?? this.useIsolate,
      useStreaming: useStreaming ?? this.useStreaming,
      requiresMemoryCheck: requiresMemoryCheck ?? this.requiresMemoryCheck,
      requiresCleanup: requiresCleanup ?? this.requiresCleanup,
      maxRetries: maxRetries ?? this.maxRetries,
      timeout: timeout ?? this.timeout,
      fallbackStrategy: fallbackStrategy ?? this.fallbackStrategy,
    );
  }
}
