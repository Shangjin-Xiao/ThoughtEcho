import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/jank_detector.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

class FakeUnifiedLogService implements UnifiedLogService {
  final List<String> warnings = [];

  @override
  void warning(String message,
      {dynamic error, String? source, StackTrace? stackTrace}) {
    warnings.add(message);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('卡顿阈值跟着屏幕刷新率走，而不是写死 60Hz', (WidgetTester tester) async {
    // 原来写死 32ms 并注明「基于 60fps」。120Hz 屏一帧只有 8.3ms，那个阈值等于
    // 连丢四帧才报一次 —— 日志里一片安静，人却明显觉得卡。
    addTearDown(tester.view.display.resetRefreshRate);

    tester.view.display.refreshRate = 60;
    expect(JankDetector.jankThresholdMicros, 33334);

    tester.view.display.refreshRate = 120;
    expect(JankDetector.jankThresholdMicros, 16666);
  });

  testWidgets('JankDetector normal, jank, throttle and session tests',
      (WidgetTester tester) async {
    final fakeLogService = FakeUnifiedLogService();
    UnifiedLogService.instanceForTesting = fakeLogService;

    JankDetector.init();

    // init 再次调用，应该直接返回 (由于 _initialized)
    JankDetector.init();

    // Normal frame: build 16ms, raster 16ms（60Hz 下一帧 16.7ms，两帧 33.3ms）
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 16000,
        rasterStart: 16000,
        rasterFinish: 32000,
        rasterFinishWallTime: 32000,
      )
    ]);

    expect(fakeLogService.warnings.isEmpty, isTrue,
        reason: 'Normal frame should not trigger log');

    // Jank frame: build 40ms, raster 10ms（超过两帧）
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 40000,
        rasterStart: 40000,
        rasterFinish: 50000,
        rasterFinishWallTime: 50000,
      )
    ]);

    expect(fakeLogService.warnings.length, 1,
        reason: 'Jank frame should trigger log');
    expect(fakeLogService.warnings.last, contains('UI构建: 40ms'));

    // Consecutive Jank frame (within 2s throttle duration): should not log
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 50000,
        rasterStart: 50000,
        rasterFinish: 60000,
        rasterFinishWallTime: 60000,
      )
    ]);

    expect(fakeLogService.warnings.length, 1,
        reason: 'Consecutive jank frame should be throttled');

    // Wait for throttle duration to pass using runAsync to avoid FakeAsync deadlocks
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 2100));
    });

    // Test with session
    JankDetector.beginSession('test_session_123');

    // Jank frame again, should log now with session (raster > 32ms)
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 10000,
        rasterStart: 10000,
        rasterFinish: 50000,
        rasterFinishWallTime: 50000,
      )
    ]);

    expect(fakeLogService.warnings.length, 2,
        reason: 'Jank frame after throttle duration should log');
    expect(fakeLogService.warnings.last, contains('session=test_session_123'));
    expect(fakeLogService.warnings.last, contains('GPU渲染: 40ms'));

    // End session correctly
    JankDetector.endSession('test_session_123');

    // Begin new session
    JankDetector.beginSession('test_session_456');
    // Try to end with wrong session ID, should not clear
    JankDetector.endSession('wrong_session');

    // Wait for throttle duration
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 2100));
    });

    // Jank frame again, should log with session 456。
    // 用 36ms 而不是 33ms：阈值现在按屏幕刷新率算（60Hz 下是两帧 33.3ms），
    // 33ms 在 60Hz 上本来就不到两帧，那个取值只对旧的写死 32ms 成立。
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 36000,
        rasterStart: 36000,
        rasterFinish: 40000,
        rasterFinishWallTime: 40000,
      )
    ]);

    expect(fakeLogService.warnings.length, 3);
    expect(fakeLogService.warnings.last, contains('session=test_session_456'));

    // Properly end it
    JankDetector.endSession('test_session_456');

    // Wait for throttle
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 2100));
    });

    // Jank frame, no session
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 35000,
        rasterStart: 35000,
        rasterFinish: 40000,
        rasterFinishWallTime: 40000,
      )
    ]);

    expect(fakeLogService.warnings.length, 4);
    expect(fakeLogService.warnings.last, isNot(contains('session=')));
  });
}
