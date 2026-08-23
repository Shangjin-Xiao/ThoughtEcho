import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/frame_timing_stats.dart';

/// 记录页的性能日志曾经把「一帧」写死成 60Hz 的 16.6ms，而且在三处各写一遍。
/// 在 120Hz 屏上那等于「连丢两帧才算一次 jank」：日志里 `frameJank=0`，人明明
/// 觉得卡。这个文件钉住两件事 —— 预算跟着刷新率走，以及「帧根本没产出」这件事
/// 能从 vsync 间隔里被数出来（build/raster 时长永远看不见它）。
FrameTiming _timing({
  required int vsyncStart,
  int vsyncOverheadMicros = 500,
  int buildMicros = 2000,
  int rasterMicros = 1000,
}) {
  final buildStart = vsyncStart + vsyncOverheadMicros;
  final buildFinish = buildStart + buildMicros;
  final rasterStart = buildFinish;
  final rasterFinish = rasterStart + rasterMicros;
  return FrameTiming(
    vsyncStart: vsyncStart,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

void main() {
  group('frameBudgetMicrosForRefreshRate', () {
    test('按真实刷新率换算一帧的预算', () {
      expect(frameBudgetMicrosForRefreshRate(120), 8333);
      expect(frameBudgetMicrosForRefreshRate(90), 11111);
      expect(frameBudgetMicrosForRefreshRate(60), 16667);
    });

    test('取不到刷新率时退回 60Hz，宁可漏报也不凭空造 jank', () {
      expect(frameBudgetMicrosForRefreshRate(0), 16667);
      expect(frameBudgetMicrosForRefreshRate(-1), 16667);
      expect(frameBudgetMicrosForRefreshRate(double.nan), 16667);
      expect(frameBudgetMicrosForRefreshRate(double.infinity), 16667);
    });
  });

  group('FrameTimingStats', () {
    test('每帧都踩在 vsync 上时既不算 jank 也不算丢帧', () {
      const budget = 8333;
      final stats = FrameTimingStats.of(
        [
          for (var i = 0; i < 5; i++) _timing(vsyncStart: i * budget),
        ],
        budgetMicros: budget,
      );

      expect(stats.frames, 5);
      expect(stats.jank, 0);
      expect(stats.dropped, 0);
      expect(stats.avgFrameMs, closeTo(3.0, 0.01));
    });

    test('同一帧在 120Hz 上是 jank，在 60Hz 上不是', () {
      final timings = [
        _timing(vsyncStart: 0),
        _timing(vsyncStart: 8333, buildMicros: 9000, rasterMicros: 3000),
      ];

      expect(FrameTimingStats.of(timings, budgetMicros: 8333).jank, 1);
      expect(FrameTimingStats.of(timings, budgetMicros: 16667).jank, 0);
    });

    test('整帧被跳过时 build/raster 看不出来，vsync 间隔能数出来', () {
      const budget = 8333;
      // 第二帧和第三帧之间空了三个 vsync 周期，但每一帧自己都很快。
      final stats = FrameTimingStats.of(
        [
          _timing(vsyncStart: 0),
          _timing(vsyncStart: budget),
          _timing(vsyncStart: budget + budget * 3),
        ],
        budgetMicros: budget,
      );

      expect(stats.jank, 0, reason: 'build+raster 都在预算内');
      expect(stats.dropped, 2, reason: '中间空掉的两帧只有 vsync 间隔看得见');
      expect(stats.worstGapMs, closeTo(budget * 3 / 1000.0, 0.01));
    });

    test('手指停住留下的长空档不算丢帧，但仍记进 worstGap', () {
      const budget = 8333;
      final stats = FrameTimingStats.of(
        [
          _timing(vsyncStart: 0),
          _timing(vsyncStart: 3000000),
        ],
        budgetMicros: budget,
      );

      expect(stats.dropped, 0);
      expect(stats.worstGapMs, closeTo(3000.0, 0.01));
    });

    test('vsync 到 build 之间的等待单独记账', () {
      final stats = FrameTimingStats.of(
        [
          _timing(vsyncStart: 0, vsyncOverheadMicros: 400),
          _timing(vsyncStart: 8333, vsyncOverheadMicros: 6200),
        ],
        budgetMicros: 8333,
      );

      expect(stats.worstVsyncOverheadMs, closeTo(6.2, 0.01));
      expect(
        stats.worstSpanMs,
        closeTo(9.2, 0.01),
        reason: 'totalSpan 要覆盖 build 之前的等待，否则这段时间无人认领',
      );
    });

    test('空样本不炸', () {
      final stats = FrameTimingStats.of(const [], budgetMicros: 8333);
      expect(stats.frames, 0);
      expect(stats.avgFrameMs, 0);
      expect(stats.dropped, 0);
    });
  });
}
