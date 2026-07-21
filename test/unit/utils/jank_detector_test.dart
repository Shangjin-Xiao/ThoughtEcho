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
  testWidgets('JankDetector normal, jank, throttle and session tests',
      (WidgetTester tester) async {
    final fakeLogService = FakeUnifiedLogService();
    UnifiedLogService.instanceForTesting = fakeLogService;

    JankDetector.init();

    // init 再次调用，应该直接返回 (由于 _initialized)
    JankDetector.init();

    // Normal frame: build 16ms, raster 16ms (under 32ms)
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

    // Jank frame: build 40ms, raster 10ms (build > 32ms)
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

    // Jank frame again, should log with session 456
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 33000,
        rasterStart: 33000,
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
