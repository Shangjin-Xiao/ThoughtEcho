import 'dart:async';
import 'dart:math' as math;
import '../utils/app_logger.dart';

/// 增强的文件处理进度和取消管理器
///
/// 提供精确的进度跟踪、智能取消机制和内存压力监控
class EnhancedProgressManager {
  static final EnhancedProgressManager _instance =
      EnhancedProgressManager._internal();
  factory EnhancedProgressManager() => _instance;
  EnhancedProgressManager._internal();

  // 活动操作跟踪
  final Map<String, OperationProgress> _activeOperations = {};
  final StreamController<ProgressEvent> _progressController =
      StreamController<ProgressEvent>.broadcast();

  // 全局取消控制
  final Map<String, CancellationController> _cancellationControllers = {};

  /// 获取进度事件流
  Stream<ProgressEvent> get progressStream => _progressController.stream;

  /// 开始新的操作
  String startOperation({
    required String operationName,
    required String description,
    int? totalSize,
    Map<String, dynamic>? metadata,
  }) {
    final operationId = _generateOperationId();

    final progress = OperationProgress(
      id: operationId,
      name: operationName,
      description: description,
      totalSize: totalSize,
      metadata: metadata ?? {},
      startTime: DateTime.now(),
    );

    _activeOperations[operationId] = progress;
    _cancellationControllers[operationId] = CancellationController();

    _emitProgressEvent(
      ProgressEvent(
        operationId: operationId,
        type: ProgressEventType.started,
        progress: progress,
      ),
    );

    logDebug('开始操作: $operationName (ID: $operationId)');
    return operationId;
  }

  /// 更新操作进度
  void updateProgress(
    String operationId, {
    int? currentSize,
    double? percentage,
    String? status,
    Map<String, dynamic>? additionalData,
  }) {
    final progress = _activeOperations[operationId];
    if (progress == null) return;

    // 更新进度数据
    if (currentSize != null) {
      progress.currentSize = currentSize;
      if (progress.totalSize != null && progress.totalSize! > 0) {
        progress.percentage = (currentSize / progress.totalSize!) * 100;
      }
    }

    if (percentage != null) {
      progress.percentage = percentage.clamp(0.0, 100.0);
    }

    if (status != null) {
      progress.status = status;
    }

    if (additionalData != null) {
      progress.metadata.addAll(additionalData);
    }

    // 计算速度和预估时间
    _calculateSpeed(progress);
    _estimateRemainingTime(progress);

    _emitProgressEvent(
      ProgressEvent(
        operationId: operationId,
        type: ProgressEventType.updated,
        progress: progress,
      ),
    );
  }

  /// 完成操作
  void completeOperation(String operationId, {String? finalStatus}) {
    final progress = _activeOperations[operationId];
    if (progress == null) return;

    progress.percentage = 100.0;
    progress.status = finalStatus ?? '完成';
    progress.endTime = DateTime.now();
    progress.isCompleted = true;

    _emitProgressEvent(
      ProgressEvent(
        operationId: operationId,
        type: ProgressEventType.completed,
        progress: progress,
      ),
    );

    logDebug('操作完成: ${progress.name} (ID: $operationId)');

    // 延迟清理，给UI时间显示完成状态
    Timer(const Duration(seconds: 2), () {
      _cleanupOperation(operationId);
    });
  }

  /// 取消操作
  void cancelOperation(String operationId, {String? reason}) {
    final controller = _cancellationControllers[operationId];
    final progress = _activeOperations[operationId];

    if (controller != null && progress != null) {
      controller.cancel(reason ?? '用户取消');
      progress.status = '已取消: ${reason ?? '用户取消'}';
      progress.isCancelled = true;
      progress.endTime = DateTime.now();

      _emitProgressEvent(
        ProgressEvent(
          operationId: operationId,
          type: ProgressEventType.cancelled,
          progress: progress,
        ),
      );

      logDebug('操作已取消: ${progress.name} (ID: $operationId)');

      Timer(const Duration(seconds: 1), () {
        _cleanupOperation(operationId);
      });
    }
  }

  /// 操作失败
  void failOperation(
    String operationId,
    String error, {
    StackTrace? stackTrace,
  }) {
    final progress = _activeOperations[operationId];
    if (progress == null) return;

    progress.status = '失败: $error';
    progress.error = error;
    progress.stackTrace = stackTrace;
    progress.isFailed = true;
    progress.endTime = DateTime.now();

    _emitProgressEvent(
      ProgressEvent(
        operationId: operationId,
        type: ProgressEventType.failed,
        progress: progress,
      ),
    );

    logDebug('操作失败: ${progress.name} (ID: $operationId), 错误: $error');

    Timer(const Duration(seconds: 5), () {
      _cleanupOperation(operationId);
    });
  }

  /// 获取取消控制器
  CancellationController? getCancellationController(String operationId) {
    return _cancellationControllers[operationId];
  }

  /// 获取操作进度
  OperationProgress? getOperationProgress(String operationId) {
    return _activeOperations[operationId];
  }

  /// 获取所有活动操作
  List<OperationProgress> getActiveOperations() {
    return _activeOperations.values
        .where((op) => !op.isCompleted && !op.isCancelled && !op.isFailed)
        .toList();
  }

  /// 取消所有操作
  void cancelAllOperations({String? reason}) {
    final activeIds = _activeOperations.keys.toList();
    for (final id in activeIds) {
      cancelOperation(id, reason: reason);
    }
  }

  /// 生成操作ID
  String _generateOperationId() {
    return 'op_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
  }

  /// 计算传输速度
  void _calculateSpeed(OperationProgress progress) {
    final now = DateTime.now();
    final elapsed = now.difference(progress.startTime).inMilliseconds;

    if (elapsed > 0 && progress.currentSize > 0) {
      // 计算平均速度 (字节/秒)
      progress.averageSpeed = (progress.currentSize / elapsed) * 1000;

      // 计算瞬时速度 (使用最近1秒的数据)
      final recentSamples = progress.speedSamples.where((sample) {
        return now.difference(sample.timestamp).inSeconds <= 1;
      }).toList();

      if (recentSamples.isNotEmpty) {
        final totalBytes = recentSamples.fold<int>(
          0,
          (sum, sample) => sum + sample.bytes,
        );
        final totalTime = recentSamples.fold<int>(
          0,
          (sum, sample) => sum + sample.intervalMs,
        );

        if (totalTime > 0) {
          progress.instantSpeed = (totalBytes / totalTime) * 1000;
        }
      }

      // 添加新的速度样本
      progress.speedSamples.add(
        SpeedSample(
          timestamp: now,
          bytes: progress.currentSize,
          intervalMs: elapsed,
        ),
      );

      // 限制样本数量
      if (progress.speedSamples.length > 100) {
        progress.speedSamples.removeAt(0);
      }
    }
  }

  /// 估算剩余时间
  void _estimateRemainingTime(OperationProgress progress) {
    if (progress.totalSize != null && progress.averageSpeed > 0) {
      final remainingBytes = progress.totalSize! - progress.currentSize;
      if (remainingBytes > 0) {
        progress.estimatedRemainingTime = Duration(
          seconds: (remainingBytes / progress.averageSpeed).round(),
        );
      }
    }
  }

  /// 发出进度事件
  void _emitProgressEvent(ProgressEvent event) {
    _progressController.add(event);
  }

  /// 清理操作
  void _cleanupOperation(String operationId) {
    _activeOperations.remove(operationId);
    _cancellationControllers.remove(operationId);
  }
}

/// 操作进度
class OperationProgress {
  final String id;
  final String name;
  final String description;
  final int? totalSize;
  final Map<String, dynamic> metadata;
  final DateTime startTime;

  int currentSize = 0;
  double percentage = 0.0;
  String status = '准备中';
  double averageSpeed = 0.0;
  double instantSpeed = 0.0;
  Duration? estimatedRemainingTime;
  DateTime? endTime;
  String? error;
  StackTrace? stackTrace;
  bool isCompleted = false;
  bool isCancelled = false;
  bool isFailed = false;

  final List<SpeedSample> speedSamples = [];

  OperationProgress({
    required this.id,
    required this.name,
    required this.description,
    this.totalSize,
    required this.metadata,
    required this.startTime,
  });

  /// 获取格式化的速度字符串
  String get formattedSpeed {
    final speed = instantSpeed > 0 ? instantSpeed : averageSpeed;
    if (speed < 1024) {
      return '${speed.toStringAsFixed(0)} B/s';
    } else if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(speed / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
  }

  /// 获取格式化的剩余时间字符串
  String get formattedRemainingTime {
    if (estimatedRemainingTime == null) return '未知';

    final seconds = estimatedRemainingTime!.inSeconds;
    if (seconds < 60) {
      return '$seconds秒';
    } else if (seconds < 3600) {
      return '${(seconds / 60).round()}分钟';
    } else {
      return '${(seconds / 3600).round()}小时';
    }
  }

  /// 获取格式化的文件大小字符串
  String get formattedSize {
    if (totalSize == null) return '未知大小';

    final size = totalSize!;
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
  }
}

/// 速度样本
class SpeedSample {
  final DateTime timestamp;
  final int bytes;
  final int intervalMs;

  SpeedSample({
    required this.timestamp,
    required this.bytes,
    required this.intervalMs,
  });
}

/// 取消控制器
class CancellationController {
  bool _isCancelled = false;
  String? _reason;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;
  Future<void> get future => _completer.future;

  void cancel([String? reason]) {
    if (!_isCancelled) {
      _isCancelled = true;
      _reason = reason;
      _completer.complete();
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCancelledException(_reason ?? '操作已取消');
    }
  }
}

/// 进度事件
class ProgressEvent {
  final String operationId;
  final ProgressEventType type;
  final OperationProgress progress;

  ProgressEvent({
    required this.operationId,
    required this.type,
    required this.progress,
  });
}

/// 进度事件类型
enum ProgressEventType {
  started, // 开始
  updated, // 更新
  completed, // 完成
  cancelled, // 取消
  failed, // 失败
}

/// 操作取消异常
class OperationCancelledException implements Exception {
  final String message;

  OperationCancelledException(this.message);

  @override
  String toString() => 'OperationCancelledException: $message';
}
