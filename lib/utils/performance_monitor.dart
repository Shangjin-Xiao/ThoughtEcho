import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_logger.dart';

/// 性能监控工具 - 用于诊断和优化性能问题
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final Map<String, _PerformanceMetrics> _metrics = {};
  bool _isMonitoring = false;
  
  /// 开始监控一个操作
  void startMeasure(String name) {
    _metrics[name] = _PerformanceMetrics(name: name);
  }
  
  /// 结束监控并记录结果
  void endMeasure(String name) {
    final metric = _metrics[name];
    if (metric != null) {
      metric.end();
      
      final platform = _getPlatformName();
      logDebug(
        '⏱️ [$platform] $name: ${metric.duration}ms',
        source: 'Performance',
      );
      
      // 如果超过阈值，输出警告
      if (metric.duration > 50) {
        logWarning(
          '⚠️ 性能警告: $name 耗时 ${metric.duration}ms (超过50ms)',
          source: 'Performance',
        );
      }
    }
  }
  
  /// 测量一个异步操作的性能
  Future<T> measureAsync<T>(String name, Future<T> Function() operation) async {
    startMeasure(name);
    try {
      return await operation();
    } finally {
      endMeasure(name);
    }
  }
  
  /// 测量一个同步操作的性能
  T measureSync<T>(String name, T Function() operation) {
    startMeasure(name);
    try {
      return operation();
    } finally {
      endMeasure(name);
    }
  }
  
  /// 监控帧率
  void startFrameMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    
    int frameCount = 0;
    int droppedFrames = 0;
    DateTime lastCheck = DateTime.now();
    
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      if (!_isMonitoring) return;
      
      for (final timing in timings) {
        frameCount++;
        final buildDuration = timing.buildDuration.inMilliseconds;
        final rasterDuration = timing.rasterDuration.inMilliseconds;
        
        // 检测掉帧（超过16.67ms）
        if (buildDuration > 16 || rasterDuration > 16) {
          droppedFrames++;
        }
      }
      
      // 每3秒报告一次
      final now = DateTime.now();
      if (now.difference(lastCheck).inSeconds >= 3) {
        final fps = frameCount / 3.0;
        final dropRate = (droppedFrames / frameCount * 100).toStringAsFixed(1);
        
        logDebug(
          '📊 [${_getPlatformName()}] FPS: ${fps.toStringAsFixed(1)}, 掉帧率: $dropRate%',
          source: 'Performance',
        );
        
        frameCount = 0;
        droppedFrames = 0;
        lastCheck = now;
      }
    });
  }
  
  /// 停止帧率监控
  void stopFrameMonitoring() {
    _isMonitoring = false;
  }
  
  /// 获取所有性能指标
  Map<String, dynamic> getMetrics() {
    return _metrics.map((key, value) => MapEntry(key, {
      'name': value.name,
      'duration': value.duration,
      'timestamp': value.startTime.toIso8601String(),
    }));
  }
  
  /// 清除所有指标
  void clearMetrics() {
    _metrics.clear();
  }
  
  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}

class _PerformanceMetrics {
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  
  _PerformanceMetrics({required this.name}) : startTime = DateTime.now();
  
  void end() {
    endTime = DateTime.now();
  }
  
  int get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inMilliseconds;
  }
}

/// 性能测试Widget包装器
class PerformanceTestWidget extends StatefulWidget {
  final Widget child;
  final String widgetName;
  
  const PerformanceTestWidget({
    super.key,
    required this.child,
    required this.widgetName,
  });
  
  @override
  State<PerformanceTestWidget> createState() => _PerformanceTestWidgetState();
}

class _PerformanceTestWidgetState extends State<PerformanceTestWidget> {
  final _monitor = PerformanceMonitor();
  
  @override
  Widget build(BuildContext context) {
    return _monitor.measureSync(
      '${widget.widgetName}.build',
      () => widget.child,
    );
  }
}
