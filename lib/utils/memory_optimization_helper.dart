import 'device_memory_manager.dart';
import 'app_logger.dart';

/// 内存优化助手
///
/// 提供智能的内存管理策略和优化建议
class MemoryOptimizationHelper {
  static final MemoryOptimizationHelper _instance =
      MemoryOptimizationHelper._internal();
  factory MemoryOptimizationHelper() => _instance;
  MemoryOptimizationHelper._internal();

  final DeviceMemoryManager _memoryManager = DeviceMemoryManager();

  /// 根据当前内存状态获取最佳处理策略
  Future<ProcessingStrategy> getOptimalStrategy(int dataSize) async {
    try {
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();
      final availableMemory = await _memoryManager.getAvailableMemory();

      // 根据内存压力和数据大小决定策略
      if (memoryPressure >= 3) {
        // 临界状态
        return ProcessingStrategy.minimal;
      } else if (memoryPressure >= 2) {
        // 高压力
        return dataSize > 10 * 1024 * 1024
            ? ProcessingStrategy.streaming
            : ProcessingStrategy.chunked;
      } else if (dataSize > availableMemory ~/ 4) {
        return ProcessingStrategy.streaming;
      } else if (dataSize > 50 * 1024 * 1024) {
        return ProcessingStrategy.chunked;
      } else {
        return ProcessingStrategy.direct;
      }
    } catch (e) {
      logDebug('获取处理策略失败: $e');
      return ProcessingStrategy.chunked; // 默认使用分块策略
    }
  }

  /// 获取最佳块大小
  Future<int> getOptimalChunkSize(int dataSize) async {
    try {
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();
      final availableMemory = await _memoryManager.getAvailableMemory();

      // 基础块大小
      int baseChunkSize = 64 * 1024; // 64KB

      // 根据内存压力调整
      switch (memoryPressure) {
        case 3: // 临界状态
          baseChunkSize = 8 * 1024; // 8KB
          break;
        case 2: // 高压力
          baseChunkSize = 16 * 1024; // 16KB
          break;
        case 1: // 中等压力
          baseChunkSize = 32 * 1024; // 32KB
          break;
        case 0: // 正常状态
        default:
          baseChunkSize = 128 * 1024; // 128KB
          break;
      }

      // 根据可用内存调整
      final maxSafeChunkSize = availableMemory ~/ 100; // 可用内存的1%
      baseChunkSize = baseChunkSize.clamp(8 * 1024, maxSafeChunkSize);

      // 根据数据大小调整
      if (dataSize > 1024 * 1024 * 1024) {
        // 1GB以上
        baseChunkSize = (baseChunkSize * 0.5).round();
      } else if (dataSize < 1024 * 1024) {
        // 1MB以下
        baseChunkSize = (baseChunkSize * 2).round();
      }

      return baseChunkSize.clamp(8 * 1024, 2 * 1024 * 1024); // 8KB - 2MB
    } catch (e) {
      logDebug('计算最佳块大小失败: $e');
      return 32 * 1024; // 默认32KB
    }
  }

  /// 检查是否应该使用Isolate
  Future<bool> shouldUseIsolate(int dataSize) async {
    try {
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();

      // 高内存压力时避免使用Isolate
      if (memoryPressure >= 2) {
        // 高压力或临界状态
        return false;
      }

      // 只有在数据非常大且内存充足时才使用Isolate
      return dataSize > 100 * 1024 * 1024; // 100MB以上
    } catch (e) {
      logDebug('检查Isolate使用策略失败: $e');
      return false; // 默认不使用
    }
  }

  /// 执行内存优化清理
  Future<void> performOptimization() async {
    try {
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();

      if (memoryPressure >= 3) {
        // 临界状态需要暂停
        logDebug('执行紧急内存优化...');

        // 清理缓存
        _memoryManager.clearCache();

        // 触发垃圾回收
        await _memoryManager.suggestGarbageCollection();

        // 等待一段时间让系统回收内存
        await Future.delayed(const Duration(milliseconds: 500));

        logDebug('内存优化完成');
      }
    } catch (e) {
      logDebug('内存优化失败: $e');
    }
  }

  /// 监控内存使用并在必要时优化
  Future<void> monitorAndOptimize() async {
    try {
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();

      if (memoryPressure >= 2) {
        // 高压力或临界状态需要警告
        final description = _getPressureDescription(memoryPressure);
        logDebug('内存压力警告: $description');
        await performOptimization();
      }
    } catch (e) {
      logDebug('内存监控失败: $e');
    }
  }

  /// 获取内存压力描述
  String _getPressureDescription(int pressureLevel) {
    switch (pressureLevel) {
      case 0:
        return '内存充足';
      case 1:
        return '内存使用正常';
      case 2:
        return '内存使用较高';
      case 3:
        return '内存不足';
      default:
        return '内存状态未知';
    }
  }
}

/// 处理策略枚举
enum ProcessingStrategy {
  direct, // 直接处理（小数据，内存充足）
  chunked, // 分块处理（中等数据）
  streaming, // 流式处理（大数据）
  minimal, // 最小化处理（内存不足）
}

/// 处理策略扩展
extension ProcessingStrategyExt on ProcessingStrategy {
  String get description {
    switch (this) {
      case ProcessingStrategy.direct:
        return '直接处理';
      case ProcessingStrategy.chunked:
        return '分块处理';
      case ProcessingStrategy.streaming:
        return '流式处理';
      case ProcessingStrategy.minimal:
        return '最小化处理';
    }
  }

  bool get useIsolate {
    switch (this) {
      case ProcessingStrategy.direct:
        return false;
      case ProcessingStrategy.chunked:
        return false;
      case ProcessingStrategy.streaming:
        return false; // 流式处理通常不需要Isolate
      case ProcessingStrategy.minimal:
        return false;
    }
  }
}
