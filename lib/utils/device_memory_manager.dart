import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_logger.dart';

/// 设备内存管理器
///
/// 提供设备内存检测、监控和优化建议
/// 支持实时内存监控和压力管理
class DeviceMemoryManager {
  static final DeviceMemoryManager _instance = DeviceMemoryManager._internal();
  factory DeviceMemoryManager() => _instance;
  DeviceMemoryManager._internal();

  // 内存信息缓存
  int? _totalMemory;
  DateTime? _lastCheck;
  static const Duration _cacheTimeout = Duration(seconds: 5);

  // 内存监控相关
  bool _isMonitoring = false;
  StreamController<Map<String, dynamic>>? _memoryStatusController;

  // 内存压力级别缓存
  int _lastPressureLevel = 0;
  DateTime? _lastPressureCheck;

  /// 获取设备总内存（字节）
  Future<int> getTotalMemory() async {
    try {
      if (_totalMemory != null &&
          _lastCheck != null &&
          DateTime.now().difference(_lastCheck!) < _cacheTimeout) {
        return _totalMemory!;
      }

      if (kIsWeb) {
        // Web平台返回一个合理的估计值
        return 4 * 1024 * 1024 * 1024; // 4GB
      }

      if (Platform.isAndroid) {
        try {
          final result = await _getAndroidMemoryInfo();
          _totalMemory = result['total'] ?? 4 * 1024 * 1024 * 1024;
        } catch (e) {
          logDebug('获取Android内存信息失败: $e');
          _totalMemory = 4 * 1024 * 1024 * 1024; // 默认4GB
        }
      } else if (Platform.isIOS) {
        try {
          final result = await _getIOSMemoryInfo();
          _totalMemory = result['total'] ?? 4 * 1024 * 1024 * 1024;
        } catch (e) {
          logDebug('获取iOS内存信息失败: $e');
          _totalMemory = 4 * 1024 * 1024 * 1024; // 默认4GB
        }
      } else {
        // 桌面平台使用更保守的估计
        _totalMemory = 8 * 1024 * 1024 * 1024; // 默认8GB
      }

      _lastCheck = DateTime.now();
      return _totalMemory!;
    } catch (e) {
      logDebug('获取总内存失败: $e');
      return 4 * 1024 * 1024 * 1024; // 默认4GB
    }
  }

  /// 获取可用内存（字节）
  Future<int> getAvailableMemory() async {
    try {
      if (kIsWeb) {
        // Web平台返回一个保守的估计值
        return 1 * 1024 * 1024 * 1024; // 1GB
      }

      if (Platform.isAndroid) {
        try {
          final result = await _getAndroidMemoryInfo();
          return result['available'] ?? 1 * 1024 * 1024 * 1024;
        } catch (e) {
          logDebug('获取Android可用内存失败: $e');
          return 1 * 1024 * 1024 * 1024;
        }
      } else if (Platform.isIOS) {
        try {
          final result = await _getIOSMemoryInfo();
          return result['available'] ?? 1 * 1024 * 1024 * 1024;
        } catch (e) {
          logDebug('获取iOS可用内存失败: $e');
          return 1 * 1024 * 1024 * 1024;
        }
      } else {
        // 桌面平台假设有更多可用内存
        return 2 * 1024 * 1024 * 1024; // 默认2GB
      }
    } catch (e) {
      logDebug('获取可用内存失败: $e');
      return 1 * 1024 * 1024 * 1024; // 默认1GB
    }
  }

  /// 获取内存使用率（0.0 - 1.0）
  Future<double> getMemoryUsageRatio() async {
    try {
      final total = await getTotalMemory();
      final available = await getAvailableMemory();
      final used = total - available;
      return used / total;
    } catch (e) {
      logDebug('计算内存使用率失败: $e');
      return 0.5; // 默认50%
    }
  }

  /// 检查是否有足够内存处理指定大小的文件
  Future<bool> canProcessFile(int fileSize) async {
    try {
      final available = await getAvailableMemory();

      // 保守策略：文件大小不应超过可用内存的1/4
      // 这给系统留下足够的缓冲空间
      final maxSafeSize = available ~/ 4;

      logDebug(
        '内存检查: 文件大小=${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB, '
        '可用内存=${(available / 1024 / 1024).toStringAsFixed(1)}MB, '
        '安全限制=${(maxSafeSize / 1024 / 1024).toStringAsFixed(1)}MB',
      );

      return fileSize <= maxSafeSize;
    } catch (e) {
      logDebug('内存检查失败: $e');
      // 出错时采用保守策略
      return fileSize <= 50 * 1024 * 1024; // 50MB
    }
  }

  /// 根据可用内存推荐最佳块大小
  Future<int> getOptimalChunkSize(int fileSize) async {
    try {
      final usageRatio = await getMemoryUsageRatio();

      // 基础块大小
      int baseChunkSize = 64 * 1024; // 64KB

      // 根据内存压力调整
      if (usageRatio > 0.8) {
        // 高内存压力：使用很小的块
        baseChunkSize = 8 * 1024; // 8KB
      } else if (usageRatio > 0.6) {
        // 中等内存压力：使用较小的块
        baseChunkSize = 16 * 1024; // 16KB
      } else if (usageRatio < 0.3) {
        // 低内存压力：可以使用较大的块
        baseChunkSize = 128 * 1024; // 128KB
      }

      // 根据文件大小调整
      if (fileSize > 1024 * 1024 * 1024) {
        // 1GB以上的文件使用更小的块
        baseChunkSize = math.min(baseChunkSize, 16 * 1024);
      } else if (fileSize < 10 * 1024 * 1024) {
        // 10MB以下的文件可以使用更大的块
        baseChunkSize = math.max(baseChunkSize, 64 * 1024);
      }

      logDebug(
        '推荐块大小: ${(baseChunkSize / 1024).toStringAsFixed(1)}KB '
        '(文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB, '
        '内存使用率: ${(usageRatio * 100).toStringAsFixed(1)}%)',
      );

      return baseChunkSize;
    } catch (e) {
      logDebug('计算最佳块大小失败: $e');
      return 32 * 1024; // 默认32KB
    }
  }

  /// 检查当前内存压力级别（枚举版本）
  Future<MemoryPressureLevel> getMemoryPressureLevelEnum() async {
    try {
      final level = await getMemoryPressureLevel();

      switch (level) {
        case 0:
          return MemoryPressureLevel.low;
        case 1:
          return MemoryPressureLevel.medium;
        case 2:
          return MemoryPressureLevel.high;
        case 3:
          return MemoryPressureLevel.critical;
        default:
          return MemoryPressureLevel.medium;
      }
    } catch (e) {
      logDebug('检查内存压力级别失败: $e');
      return MemoryPressureLevel.medium; // 出错时返回中等压力
    }
  }

  /// 获取Android内存信息
  Future<Map<String, int>> _getAndroidMemoryInfo() async {
    try {
      const platform = MethodChannel('thoughtecho/memory_info');
      try {
        final result = await platform.invokeMethod('getMemoryInfo');

        // 使用真实的内存信息
        final totalMem = result['totalMem'] as int? ?? 4 * 1024 * 1024 * 1024;
        final availMem = result['availMem'] as int? ?? 1 * 1024 * 1024 * 1024;
        final appMaxMemory =
            result['appMaxMemory'] as int? ?? 512 * 1024 * 1024;
        final appUsedMemory =
            result['appUsedMemory'] as int? ?? 256 * 1024 * 1024;
        final lowMemory = result['lowMemory'] as bool? ?? false;

        logDebug(
          'Android内存信息: 总内存=${(totalMem / 1024 / 1024).toStringAsFixed(0)}MB, '
          '可用=${(availMem / 1024 / 1024).toStringAsFixed(0)}MB, '
          '应用最大=${(appMaxMemory / 1024 / 1024).toStringAsFixed(0)}MB, '
          '应用已用=${(appUsedMemory / 1024 / 1024).toStringAsFixed(0)}MB, '
          '低内存警告=$lowMemory',
        );

        // 如果系统报告低内存，调整可用内存估算
        final adjustedAvailMem = lowMemory
            ? (availMem * 0.5).toInt()
            : availMem;

        return {
          'total': totalMem,
          'available': adjustedAvailMem,
          'appMaxMemory': appMaxMemory,
          'appUsedMemory': appUsedMemory,
        };
      } catch (e) {
        // 如果原生方法不可用，返回保守估计值
        logDebug('原生内存检测不可用，使用估计值: $e');
        return {
          'total': 4 * 1024 * 1024 * 1024, // 4GB
          'available': 512 * 1024 * 1024, // 512MB - 更保守的估计
        };
      }
    } catch (e) {
      throw Exception('获取Android内存信息失败: $e');
    }
  }

  /// 获取iOS内存信息
  Future<Map<String, int>> _getIOSMemoryInfo() async {
    try {
      // 这里应该使用原生方法获取实际的内存信息
      // 为了简化，现在返回估计值

      const platform = MethodChannel('thoughtecho/memory_info');
      try {
        final result = await platform.invokeMethod('getMemoryInfo');
        return {
          'total': result['totalMem'] ?? 4 * 1024 * 1024 * 1024,
          'available': result['availMem'] ?? 1 * 1024 * 1024 * 1024,
        };
      } catch (e) {
        // 如果原生方法不可用，返回保守估计值
        logDebug('原生内存检测不可用，使用估计值: $e');
        return {
          'total': 4 * 1024 * 1024 * 1024, // 4GB
          'available': 1 * 1024 * 1024 * 1024, // 1GB
        };
      }
    } catch (e) {
      throw Exception('获取iOS内存信息失败: $e');
    }
  }

  /// 触发垃圾回收建议
  Future<void> suggestGarbageCollection() async {
    try {
      // 创建一些垃圾对象来触发GC
      List<List<int>>? tempLists = [];
      for (int i = 0; i < 100; i++) {
        tempLists.add(List.filled(1000, 0));
      }
      tempLists = null;

      // 给GC一些时间
      await Future.delayed(const Duration(milliseconds: 100));

      logDebug('已建议执行垃圾回收');
    } catch (e) {
      logDebug('触发垃圾回收失败: $e');
    }
  }

  /// 获取内存压力级别（增强版）
  Future<int> getMemoryPressureLevel() async {
    try {
      // 检查缓存
      if (_lastPressureCheck != null &&
          DateTime.now().difference(_lastPressureCheck!) <
              const Duration(seconds: 2)) {
        return _lastPressureLevel;
      }

      if (Platform.isAndroid) {
        try {
          const platform = MethodChannel('thoughtecho/memory_info');
          final pressureLevel = await platform.invokeMethod(
            'getMemoryPressureLevel',
          );
          _lastPressureLevel = pressureLevel ?? 1;
          _lastPressureCheck = DateTime.now();
          return _lastPressureLevel;
        } catch (e) {
          logDebug('获取原生内存压力级别失败: $e');
        }
      }

      // 回退到计算方式
      final usageRatio = await getMemoryUsageRatio();
      int level;
      if (usageRatio >= 0.95) {
        level = 3; // 临界状态
      } else if (usageRatio >= 0.85) {
        level = 2; // 高压力
      } else if (usageRatio >= 0.6) {
        level = 1; // 中等压力
      } else {
        level = 0; // 正常状态
      }

      _lastPressureLevel = level;
      _lastPressureCheck = DateTime.now();
      return level;
    } catch (e) {
      logDebug('获取内存压力级别失败: $e');
      return 1; // 出错时返回中等压力
    }
  }

  /// 开始内存监控
  Future<void> startMemoryMonitoring({int intervalMs = 5000}) async {
    if (_isMonitoring) {
      return;
    }

    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('thoughtecho/memory_info');

        // 设置内存状态更新回调
        platform.setMethodCallHandler((call) async {
          if (call.method == 'onMemoryStatusUpdate') {
            final data = Map<String, dynamic>.from(call.arguments);
            _memoryStatusController?.add(data);
          } else if (call.method == 'onMemoryMonitoringError') {
            final error = call.arguments['error'] as String?;
            logDebug('内存监控错误: $error');
          }
        });

        // 启动原生监控
        await platform.invokeMethod('startMemoryMonitoring', {
          'intervalMs': intervalMs,
        });

        _isMonitoring = true;
        logDebug('内存监控已启动');
      }
    } catch (e) {
      logDebug('启动内存监控失败: $e');
    }
  }

  /// 停止内存监控
  Future<void> stopMemoryMonitoring() async {
    if (!_isMonitoring) {
      return;
    }

    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('thoughtecho/memory_info');
        await platform.invokeMethod('stopMemoryMonitoring');
      }

      _isMonitoring = false;
      await _memoryStatusController?.close();
      _memoryStatusController = null;
      logDebug('内存监控已停止');
    } catch (e) {
      logDebug('停止内存监控失败: $e');
    }
  }

  /// 获取内存状态流
  Stream<Map<String, dynamic>>? get memoryStatusStream {
    _memoryStatusController ??=
        StreamController<Map<String, dynamic>>.broadcast();
    return _memoryStatusController?.stream;
  }

  /// 强制垃圾回收
  Future<void> forceGarbageCollection() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('thoughtecho/memory_info');
        await platform.invokeMethod('forceGarbageCollection');
      } else {
        // 回退到Dart的垃圾回收建议
        await suggestGarbageCollection();
      }
      logDebug('已执行强制垃圾回收');
    } catch (e) {
      logDebug('强制垃圾回收失败: $e');
    }
  }

  /// 获取详细内存信息
  Future<Map<String, dynamic>> getDetailedMemoryInfo() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('thoughtecho/memory_info');
        final result = await platform.invokeMethod('getDetailedMemoryInfo');
        return Map<String, dynamic>.from(result);
      } else {
        // 回退到基础信息
        final basicInfo = await _getAndroidMemoryInfo();
        return basicInfo;
      }
    } catch (e) {
      logDebug('获取详细内存信息失败: $e');
      return {};
    }
  }

  /// 清理内存缓存
  void clearCache() {
    _totalMemory = null;
    _lastCheck = null;
    _lastPressureLevel = 0;
    _lastPressureCheck = null;
  }
}

/// 内存压力级别
enum MemoryPressureLevel {
  low, // 低压力 (<60%)
  medium, // 中等压力 (60-80%)
  high, // 高压力 (80-90%)
  critical, // 临界压力 (>90%)
}

/// 内存压力级别扩展
extension MemoryPressureLevelExt on MemoryPressureLevel {
  /// 获取描述文本
  String get description {
    switch (this) {
      case MemoryPressureLevel.low:
        return '内存充足';
      case MemoryPressureLevel.medium:
        return '内存使用正常';
      case MemoryPressureLevel.high:
        return '内存使用较高';
      case MemoryPressureLevel.critical:
        return '内存不足';
    }
  }

  /// 获取建议操作
  String get suggestion {
    switch (this) {
      case MemoryPressureLevel.low:
        return '可以正常处理大文件';
      case MemoryPressureLevel.medium:
        return '建议关闭其他应用程序';
      case MemoryPressureLevel.high:
        return '请关闭其他应用程序，使用较小的文件';
      case MemoryPressureLevel.critical:
        return '内存严重不足，请重启应用或使用更小的文件';
    }
  }

  /// 是否应该暂停处理
  bool get shouldPause {
    return this == MemoryPressureLevel.critical;
  }

  /// 是否应该警告用户
  bool get shouldWarn {
    return this == MemoryPressureLevel.high ||
        this == MemoryPressureLevel.critical;
  }
}
