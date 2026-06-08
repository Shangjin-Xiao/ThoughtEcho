import 'package:flutter/scheduler.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

/// 零开销的 UI 卡顿/掉帧自动检测器
class JankDetector {
  static DateTime? _lastLogTime;
  static bool _initialized = false;
  static String? _activeSessionId;
  // 防日志风暴机制：同一个卡顿周期内，最少间隔 2 秒才记录一次
  static const _throttleDuration = Duration(seconds: 2);

  static void beginSession(String sessionId) {
    _activeSessionId = sessionId;
  }

  static void endSession(String sessionId) {
    if (_activeSessionId == sessionId) {
      _activeSessionId = null;
    }
  }

  static void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMilliseconds;
        final rasterMs = timing.rasterDuration.inMilliseconds;

        // 阈值：32ms 约等于连丢两帧 (基于 60fps 屏幕 16.6ms/帧)
        if (buildMs > 32 || rasterMs > 32) {
          final now = DateTime.now();
          // 触发节流阀，避免动画持续卡顿时疯狂写入数据库
          if (_lastLogTime == null ||
              now.difference(_lastLogTime!) > _throttleDuration) {
            _lastLogTime = now;
            final session = _activeSessionId;
            UnifiedLogService.instance.warning(
              '⚠️ [UI卡顿] 严重掉帧! '
              '${session == null ? '' : 'session=$session, '}'
              'UI构建: ${buildMs}ms, GPU渲染: ${rasterMs}ms',
              source: 'JankDetector',
            );
          }
        }
      }
    });
  }
}
