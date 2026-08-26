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
///
/// **但「没出帧」不等于「丢帧」**：列表停着不动时 Flutter 本来就不产出帧，那段
/// 空档是省电不是卡顿。2026-08-26 的日志里有一段 `dist=-53`（手指按着几乎没挪）
/// 却报 `dropped=179`，读的人会以为卡成一片。所以要靠 [movedBetweenFrames] 逐对
/// 甄别：只有相邻两帧之间列表真的挪过，中间的空档才算丢帧。
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
    required this.idleGaps,
  });

  /// 手指停住、惯性走完都会在时间戳上留下一段很长的空档，那不是卡顿而是「没在滑」。
  /// 超过这个长度的间隔只记进 [worstGapMs]，不折算成丢帧。
  static const int maxCountedGapMicros = 200000;

  /// [movedBetweenFrames] 回答「这两帧之间列表挪过没有」，参数是两帧的
  /// `frameNumber`。传 null 就退回旧口径（一律算丢帧），只有拿不到逐帧偏移的
  /// 调用方才该这么用。
  factory FrameTimingStats.of(
    List<FrameTiming> timings, {
    required int budgetMicros,
    bool Function(int previousFrameNumber, int frameNumber)? movedBetweenFrames,
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
    var idleGaps = 0;
    int? previousVsync;
    int? previousFrameNumber;

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
      final previousNumber = previousFrameNumber;
      if (previous != null) {
        final gap = vsync - previous;
        if (gap > worstGap) worstGap = gap;
        if (gap > 0 && gap < maxCountedGapMicros) {
          final skipped = (gap / budgetMicros).round() - 1;
          if (skipped > 0) {
            final moved = movedBetweenFrames == null ||
                previousNumber == null ||
                movedBetweenFrames(previousNumber, timing.frameNumber);
            if (moved) {
              dropped += skipped;
            } else {
              idleGaps += skipped;
            }
          }
        }
      }
      previousVsync = vsync;
      previousFrameNumber = timing.frameNumber;
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
      idleGaps: idleGaps,
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

  /// 空档里「列表没动、本来就不该出帧」的那部分，不计进 [dropped]。
  /// 它大而 [dropped] 小，说明这一段用户基本没在滑。
  final int idleGaps;

  String toCompactText() {
    return 'budget=${(budgetMicros / 1000.0).toStringAsFixed(1)}ms, '
        'frames=$frames, frameJank=$jank, dropped=$dropped, idle=$idleGaps, '
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
