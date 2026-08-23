import 'dart:ui' show FramePhase, FrameTiming;

/// 一块屏幕上「一帧有多少微秒」。120Hz 是 8333，60Hz 是 16667。
///
/// 记录页的性能日志原来把这个数写死成 `16600`（60Hz 的一帧），而且在三处各写了
/// 一遍。120Hz 屏上它等于「连丢两帧才算一次 jank」，于是 `frameJank=0` 和「用户
/// 明显觉得卡」可以同时成立 —— 一整轮诊断都被这个常量带偏过。
///
/// 取不到刷新率（[refreshRate] 为 0 或非有限值）时退回 60Hz：那是最宽松的一档，
/// 宁可漏报也不要凭空造出一堆 jank。上下限只用来挡住畸形取值。
int frameBudgetMicrosForRefreshRate(double refreshRate) {
  if (!refreshRate.isFinite || refreshRate <= 0) return 16667;
  return (1000000 / refreshRate).round().clamp(4000, 33334);
}

/// 一段 [FrameTiming] 的汇总。
///
/// [dropped] 是这里唯一能看见「帧根本没产出」的量。`buildDuration` 和
/// `rasterDuration` 只覆盖引擎真的开工的那两段：vsync 到 build 之间的等待不进账，
/// 整帧被跳过更不会留下任何 [FrameTiming]。只有拿相邻两帧的 vsync 时间戳去除以
/// 一帧的预算，才数得出中间空掉了几帧 —— 而那正是「build+raster 都只有 3ms，
/// 滑动却明显不跟手」时唯一有用的那个数。
class FrameTimingStats {
  const FrameTimingStats({
    required this.budgetMicros,
    required this.frames,
    required this.jank,
    required this.dropped,
    required this.avgFrameMs,
    required this.worstFrameMs,
    required this.avgBuildMs,
    required this.worstBuildMs,
    required this.avgRasterMs,
    required this.worstRasterMs,
    required this.avgSpanMs,
    required this.worstSpanMs,
    required this.worstVsyncOverheadMs,
    required this.worstGapMs,
  });

  /// 手指停住、惯性走完都会在时间戳上留下一段很长的空档，那不是卡顿而是「没在滑」。
  /// 超过这个长度的间隔只记进 [worstGapMs]，不折算成丢帧。
  static const int maxCountedGapMicros = 200000;

  factory FrameTimingStats.of(
    List<FrameTiming> timings, {
    required int budgetMicros,
  }) {
    var jank = 0;
    var dropped = 0;
    var totalFrame = 0;
    var totalBuild = 0;
    var totalRaster = 0;
    var totalSpan = 0;
    var worstFrame = 0;
    var worstBuild = 0;
    var worstRaster = 0;
    var worstSpan = 0;
    var worstVsyncOverhead = 0;
    var worstGap = 0;
    int? previousVsync;

    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final frame = build + raster;
      final span = timing.totalSpan.inMicroseconds;
      final vsyncOverhead = timing.vsyncOverhead.inMicroseconds;

      totalFrame += frame;
      totalBuild += build;
      totalRaster += raster;
      totalSpan += span;
      if (frame > worstFrame) worstFrame = frame;
      if (build > worstBuild) worstBuild = build;
      if (raster > worstRaster) worstRaster = raster;
      if (span > worstSpan) worstSpan = span;
      if (vsyncOverhead > worstVsyncOverhead) {
        worstVsyncOverhead = vsyncOverhead;
      }
      if (frame > budgetMicros) jank++;

      final vsync = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final previous = previousVsync;
      if (previous != null) {
        final gap = vsync - previous;
        if (gap > worstGap) worstGap = gap;
        if (gap > 0 && gap < maxCountedGapMicros) {
          final skipped = (gap / budgetMicros).round() - 1;
          if (skipped > 0) dropped += skipped;
        }
      }
      previousVsync = vsync;
    }

    final count = timings.length;
    double avg(int total) => count == 0 ? 0.0 : (total / count) / 1000.0;

    return FrameTimingStats(
      budgetMicros: budgetMicros,
      frames: count,
      jank: jank,
      dropped: dropped,
      avgFrameMs: avg(totalFrame),
      worstFrameMs: worstFrame / 1000.0,
      avgBuildMs: avg(totalBuild),
      worstBuildMs: worstBuild / 1000.0,
      avgRasterMs: avg(totalRaster),
      worstRasterMs: worstRaster / 1000.0,
      avgSpanMs: avg(totalSpan),
      worstSpanMs: worstSpan / 1000.0,
      worstVsyncOverheadMs: worstVsyncOverhead / 1000.0,
      worstGapMs: worstGap / 1000.0,
    );
  }

  final int budgetMicros;
  final int frames;

  /// build + raster 超过一帧预算的帧数。
  final int jank;

  /// 按 vsync 间隔折算出来的、根本没产出的帧数。
  final int dropped;
  final double avgFrameMs;
  final double worstFrameMs;
  final double avgBuildMs;
  final double worstBuildMs;
  final double avgRasterMs;
  final double worstRasterMs;

  /// vsync 到光栅结束的整段耗时，包含了 build+raster 之外的等待。
  final double avgSpanMs;
  final double worstSpanMs;
  final double worstVsyncOverheadMs;
  final double worstGapMs;

  String toCompactText() {
    return 'budget=${(budgetMicros / 1000.0).toStringAsFixed(1)}ms, '
        'frames=$frames, frameJank=$jank, dropped=$dropped, '
        'avgFrame=${avgFrameMs.toStringAsFixed(1)}ms, '
        'worstFrame=${worstFrameMs.toStringAsFixed(1)}ms, '
        'avgBuild=${avgBuildMs.toStringAsFixed(1)}ms, '
        'worstBuild=${worstBuildMs.toStringAsFixed(1)}ms, '
        'avgRaster=${avgRasterMs.toStringAsFixed(1)}ms, '
        'worstRaster=${worstRasterMs.toStringAsFixed(1)}ms, '
        'avgSpan=${avgSpanMs.toStringAsFixed(1)}ms, '
        'worstSpan=${worstSpanMs.toStringAsFixed(1)}ms, '
        'worstVsync=${worstVsyncOverheadMs.toStringAsFixed(1)}ms, '
        'worstGap=${worstGapMs.toStringAsFixed(1)}ms';
  }
}
