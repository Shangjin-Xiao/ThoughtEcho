import 'dart:async';
import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/device_memory_manager.dart';
import 'intelligent_memory_manager.dart';
import 'enhanced_progress_manager.dart';
import 'error_recovery_manager.dart';
import 'file_processing_fallback_manager.dart';

/// 集成的大文件处理服务
///
/// 整合所有的内存安全、错误恢复、进度跟踪和降级策略功能
/// 提供统一的大文件处理接口，防止OOM崩溃
class IntegratedLargeFileService {
  static final IntegratedLargeFileService _instance =
      IntegratedLargeFileService._internal();
  factory IntegratedLargeFileService() => _instance;
  IntegratedLargeFileService._internal();

  final DeviceMemoryManager _memoryManager = DeviceMemoryManager();
  final IntelligentMemoryManager _intelligentMemoryManager =
      IntelligentMemoryManager();
  final EnhancedProgressManager _progressManager = EnhancedProgressManager();
  final ErrorRecoveryManager _errorRecoveryManager = ErrorRecoveryManager();
  final FileProcessingFallbackManager _fallbackManager =
      FileProcessingFallbackManager();

  bool _isInitialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 初始化各个管理器
      _errorRecoveryManager.initialize();
      await _fallbackManager.initialize();

      // 启动智能内存监控
      await _intelligentMemoryManager.startIntelligentMonitoring();

      _isInitialized = true;
      logDebug('集成大文件处理服务已初始化');
    } catch (e) {
      logDebug('初始化集成大文件处理服务失败: $e');
      rethrow;
    }
  }

  /// 关闭服务
  Future<void> dispose() async {
    if (!_isInitialized) return;

    try {
      // 停止内存监控
      await _intelligentMemoryManager.stopIntelligentMonitoring();

      // 取消所有活动操作
      _progressManager.cancelAllOperations(reason: '服务关闭');

      _isInitialized = false;
      logDebug('集成大文件处理服务已关闭');
    } catch (e) {
      logDebug('关闭集成大文件处理服务失败: $e');
    }
  }

  /// 安全复制文件
  Future<void> safeCopyFile(
    String sourcePath,
    String targetPath, {
    Function(int current, int total)? onProgress,
    Function(String status)? onStatusUpdate,
    Function(String error)? onError,
  }) async {
    await _ensureInitialized();

    return await _errorRecoveryManager.executeWithRecovery(
      'safe_file_copy',
      () async {
        await _fallbackManager.copyFileWithFallback(
          sourcePath,
          targetPath,
          onProgress: onProgress,
          onStatusUpdate: onStatusUpdate,
        );
      },
      context: {
        'source_path': sourcePath,
        'target_path': targetPath,
        'operation_type': 'file_copy',
      },
    );
  }

  /// 安全导入备份
  Future<void> safeImportBackup(
    String backupPath, {
    Function(int current, int total)? onProgress,
    Function(String status)? onStatusUpdate,
    Function(String error)? onError,
  }) async {
    await _ensureInitialized();

    return await _errorRecoveryManager.executeWithRecovery(
      'safe_backup_import',
      () async {
        await _fallbackManager.importBackupWithFallback(
          backupPath,
          onProgress: onProgress,
        );
      },
      maxRetries: 2, // 备份导入重试次数较少
      context: {'backup_path': backupPath, 'operation_type': 'backup_import'},
    );
  }

  /// 安全处理媒体文件
  Future<String?> safeProcessMedia(
    String sourcePath,
    String targetDirectory, {
    String? mediaType,
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    Function(String error)? onError,
  }) async {
    await _ensureInitialized();

    return await _errorRecoveryManager.executeWithRecovery(
      'safe_media_processing',
      () async {
        return await _fallbackManager.processMediaWithFallback(
          sourcePath,
          targetDirectory,
          mediaType: mediaType,
          onProgress: onProgress,
        );
      },
      context: {
        'source_path': sourcePath,
        'target_directory': targetDirectory,
        'media_type': mediaType ?? 'unknown',
        'operation_type': 'media_processing',
      },
    );
  }

  /// 安全处理文本内容
  Future<String> safeProcessText(
    String content, {
    String? operation,
    Map<String, dynamic>? options,
    Function(String status)? onStatusUpdate,
    Function(String error)? onError,
  }) async {
    await _ensureInitialized();

    return await _errorRecoveryManager.executeWithRecovery(
      'safe_text_processing',
      () async {
        return await _fallbackManager.processTextWithFallback(
          content,
          operation: operation,
          options: options,
        );
      },
      context: {
        'content_length': content.length,
        'operation': operation ?? 'text_processing',
        'operation_type': 'text_processing',
      },
    );
  }

  /// 检查文件是否可以安全处理
  Future<FileProcessingAssessment> assessFile(String filePath) async {
    await _ensureInitialized();

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return FileProcessingAssessment(
          canProcess: false,
          riskLevel: RiskLevel.high,
          reason: '文件不存在',
          recommendedStrategy: 'none',
        );
      }

      final fileSize = await file.length();
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();
      final availableMemory = await _memoryManager.getAvailableMemory();

      // 评估处理风险
      RiskLevel riskLevel;
      String reason;
      String recommendedStrategy;
      bool canProcess = true;

      if (memoryPressure >= 3) {
        // 临界内存状态
        riskLevel = RiskLevel.critical;
        reason = '系统内存不足';
        recommendedStrategy = 'minimal';
        canProcess = fileSize < 10 * 1024 * 1024; // 只能处理10MB以下文件
      } else if (fileSize > availableMemory * 0.5) {
        // 文件大小超过可用内存的50%
        riskLevel = RiskLevel.high;
        reason = '文件过大，可能导致内存不足';
        recommendedStrategy = 'streaming';
      } else if (fileSize > 100 * 1024 * 1024 || memoryPressure >= 2) {
        // 大文件或高内存压力
        riskLevel = RiskLevel.medium;
        reason = '需要使用保守策略处理';
        recommendedStrategy = 'conservative';
      } else {
        // 正常处理
        riskLevel = RiskLevel.low;
        reason = '可以正常处理';
        recommendedStrategy = 'default';
      }

      return FileProcessingAssessment(
        canProcess: canProcess,
        riskLevel: riskLevel,
        reason: reason,
        recommendedStrategy: recommendedStrategy,
        fileSize: fileSize,
        memoryPressure: memoryPressure,
        availableMemory: availableMemory,
      );
    } catch (e) {
      logDebug('评估文件失败: $e');
      return FileProcessingAssessment(
        canProcess: false,
        riskLevel: RiskLevel.high,
        reason: '评估失败: $e',
        recommendedStrategy: 'none',
      );
    }
  }

  /// 获取系统状态
  Future<SystemStatus> getSystemStatus() async {
    await _ensureInitialized();

    try {
      final memoryInfo = await _memoryManager.getDetailedMemoryInfo();
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();
      final activeOperations = _progressManager.getActiveOperations();
      final errorStats = _errorRecoveryManager.getErrorStatistics();

      return SystemStatus(
        memoryInfo: memoryInfo,
        memoryPressure: memoryPressure,
        activeOperationsCount: activeOperations.length,
        errorStats: errorStats,
        isHealthy: memoryPressure < 3 && activeOperations.length < 5,
      );
    } catch (e) {
      logDebug('获取系统状态失败: $e');
      return SystemStatus(
        memoryInfo: {},
        memoryPressure: 1,
        activeOperationsCount: 0,
        errorStats: {},
        isHealthy: false,
        error: e.toString(),
      );
    }
  }

  /// 获取进度流
  Stream<ProgressEvent> get progressStream => _progressManager.progressStream;

  /// 获取内存压力事件流
  Stream<MemoryPressureEvent>? get memoryPressureStream =>
      _intelligentMemoryManager.pressureEventStream;

  /// 取消所有操作
  void cancelAllOperations({String? reason}) {
    _progressManager.cancelAllOperations(reason: reason ?? '用户取消');
  }

  /// 执行紧急清理
  Future<void> performEmergencyCleanup() async {
    await _ensureInitialized();

    try {
      // 取消所有操作
      cancelAllOperations(reason: '紧急清理');

      // 强制垃圾回收
      await _memoryManager.forceGarbageCollection();

      // 清理缓存
      _memoryManager.clearCache();

      logDebug('紧急清理完成');
    } catch (e) {
      logDebug('紧急清理失败: $e');
    }
  }

  /// 确保服务已初始化
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
}

/// 文件处理评估结果
class FileProcessingAssessment {
  final bool canProcess;
  final RiskLevel riskLevel;
  final String reason;
  final String recommendedStrategy;
  final int? fileSize;
  final int? memoryPressure;
  final int? availableMemory;

  FileProcessingAssessment({
    required this.canProcess,
    required this.riskLevel,
    required this.reason,
    required this.recommendedStrategy,
    this.fileSize,
    this.memoryPressure,
    this.availableMemory,
  });
}

/// 风险级别
enum RiskLevel {
  low, // 低风险
  medium, // 中等风险
  high, // 高风险
  critical, // 临界风险
}

/// 系统状态
class SystemStatus {
  final Map<String, dynamic> memoryInfo;
  final int memoryPressure;
  final int activeOperationsCount;
  final Map<String, int> errorStats;
  final bool isHealthy;
  final String? error;

  SystemStatus({
    required this.memoryInfo,
    required this.memoryPressure,
    required this.activeOperationsCount,
    required this.errorStats,
    required this.isHealthy,
    this.error,
  });

  /// 获取内存压力描述
  String get memoryPressureDescription {
    switch (memoryPressure) {
      case 0:
        return '内存充足';
      case 1:
        return '内存正常';
      case 2:
        return '内存紧张';
      case 3:
        return '内存不足';
      default:
        return '内存状态未知';
    }
  }

  /// 获取健康状态描述
  String get healthDescription {
    if (error != null) {
      return '系统错误: $error';
    } else if (isHealthy) {
      return '系统运行正常';
    } else {
      return '系统负载较高';
    }
  }
}
