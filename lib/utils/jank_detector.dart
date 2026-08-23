import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/frame_timing_stats.dart';

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

  /// 「连丢两帧」是多少微秒，按这块屏真实的刷新率算：120Hz 是 16667，
  /// 60Hz 是 33334。
  ///
  /// 原来写死 32ms 并注明「基于 60fps 屏幕 16.6ms/帧」。120Hz 屏一帧只有 8.3ms，
  /// 那个阈值等于连丢四帧才报一次，日志里于是一片安静而人明显觉得卡。取不到刷新率
  /// 时退回 60Hz 的口径，宁可漏报也不要凭空造出一堆告警。
  ///
  /// 单位是微秒不是毫秒：`Duration.inMilliseconds` 直接截断，33.9ms 的一帧读出来
  /// 是 33，正好卡在阈值下面。
  /// 刷新率走 binding 而不是 `PlatformDispatcher.instance`：测试里前者才是
  /// 能被改写的那个，后者永远是宿主机的真实屏幕。
  @visibleForTesting
  static int get jankThresholdMicros {
    final rate = SchedulerBinding
            .instance.platformDispatcher.implicitView?.display.refreshRate ??
        0.0;
    return frameBudgetMicrosForRefreshRate(rate) * 2;
  }

  static void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      final thresholdMicros = jankThresholdMicros;
      for (final timing in timings) {
        final buildMicros = timing.buildDuration.inMicroseconds;
        final rasterMicros = timing.rasterDuration.inMicroseconds;
        final buildMs = buildMicros ~/ 1000;
        final rasterMs = rasterMicros ~/ 1000;

        if (buildMicros > thresholdMicros || rasterMicros > thresholdMicros) {
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
