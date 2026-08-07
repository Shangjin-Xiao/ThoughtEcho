import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/note_list/scroll_alignment.dart';

ScrollAnchorDecision _resolve({
  double? previousOffset,
  double? pendingOffset,
  double currentPixels = 0,
  double maxScrollExtent = 0,
  bool isDragging = false,
}) {
  return resolveScrollAnchorAction(
    previousOffset: previousOffset,
    pendingOffset: pendingOffset,
    currentPixels: currentPixels,
    maxScrollExtent: maxScrollExtent,
    isDragging: isDragging,
    tolerance: 1.0,
  );
}

void main() {
  group('resolveScrollAnchorAction', () {
    test('没有偏移也没有挂起目标时什么都不做', () {
      final decision = _resolve(maxScrollExtent: 1000);

      expect(decision.action, ScrollAnchorAction.none);
    });

    test('内容仍装得下原偏移时不动位置（惯性滑动中偏移本就在变）', () {
      final decision = _resolve(
        previousOffset: 800,
        currentPixels: 900,
        maxScrollExtent: 2000,
      );

      expect(decision.action, ScrollAnchorAction.none);
    });

    test('普通分页事件中用户正向上滑，绝不能被拽回事件发生前的位置', () {
      // 分页追加数据时用户还在惯性上滑：内容装得下原偏移，说明没被夹掉，
      // 这只是用户自己滑走了。若把原偏移当还原目标就会打断惯性。
      final decision = _resolve(
        previousOffset: 5000,
        currentPixels: 4800,
        maxScrollExtent: 20000,
      );

      expect(decision.action, ScrollAnchorAction.none);
    });

    test('内容变短装不下原偏移时记住目标', () {
      final decision = _resolve(
        previousOffset: 800,
        currentPixels: 300,
        maxScrollExtent: 300,
      );

      expect(decision.action, ScrollAnchorAction.remember);
      expect(decision.targetOffset, 800);
    });

    test('列表补长到够得着时还原到原偏移', () {
      final decision = _resolve(
        previousOffset: 300,
        pendingOffset: 800,
        currentPixels: 300,
        maxScrollExtent: 900,
      );

      expect(decision.action, ScrollAnchorAction.restore);
      expect(decision.targetOffset, 800);
    });

    test('只补长了一半时必须继续挂着更深的目标，不能悄悄丢掉', () {
      // 先被夹到 300，本次事件把内容补到 600，但原偏移是 800。
      final decision = _resolve(
        previousOffset: 300,
        pendingOffset: 800,
        currentPixels: 300,
        maxScrollExtent: 600,
      );

      expect(decision.action, ScrollAnchorAction.remember);
      expect(decision.targetOffset, 800);
    });

    test('列表被压到没有滚动范围时，previousOffset 为 0 也要保住已挂起的目标', () {
      final decision = _resolve(
        previousOffset: 0,
        pendingOffset: 800,
        currentPixels: 0,
        maxScrollExtent: 0,
      );

      expect(decision.action, ScrollAnchorAction.remember);
      expect(decision.targetOffset, 800);
    });

    test('连续变短时取更深的目标，不会越记越浅', () {
      final decision = _resolve(
        previousOffset: 400,
        pendingOffset: 800,
        currentPixels: 200,
        maxScrollExtent: 200,
      );

      expect(decision.action, ScrollAnchorAction.remember);
      expect(decision.targetOffset, 800);
    });

    test('原偏移比挂起目标更深时改用原偏移', () {
      final decision = _resolve(
        previousOffset: 1200,
        pendingOffset: 800,
        currentPixels: 200,
        maxScrollExtent: 200,
      );

      expect(decision.action, ScrollAnchorAction.remember);
      expect(decision.targetOffset, 1200);
    });

    test('用户正在拖拽时只记不跳，避免打断手势', () {
      final decision = _resolve(
        previousOffset: 300,
        pendingOffset: 800,
        currentPixels: 300,
        maxScrollExtent: 900,
        isDragging: true,
      );

      expect(decision.action, ScrollAnchorAction.remember);
      expect(decision.targetOffset, 800);
    });

    test('用户已经滑得比目标更深时不再往回拽', () {
      final decision = _resolve(
        pendingOffset: 800,
        currentPixels: 1500,
        maxScrollExtent: 2000,
      );

      expect(decision.action, ScrollAnchorAction.none);
    });

    test('目标就在容差内时视作已到位', () {
      final decision = _resolve(
        pendingOffset: 800,
        currentPixels: 799.5,
        maxScrollExtent: 2000,
      );

      expect(decision.action, ScrollAnchorAction.none);
    });
  });

  group('ScrollAnchorTracker', () {
    ScrollAnchorTracker newTracker() =>
        ScrollAnchorTracker(retention: const Duration(milliseconds: 1500));

    test('记住的目标可以在有效期内取出，取出后即清空', () {
      final tracker = newTracker();
      final now = DateTime(2026, 8, 7, 12);

      tracker.remember(800, now);
      expect(tracker.hasPending, isTrue);

      expect(tracker.consume(now.add(const Duration(milliseconds: 500))), 800);
      // consume 是一次性的，调用方要按决策结果决定是否重新 remember。
      expect(tracker.hasPending, isFalse);
      expect(tracker.consume(now), isNull);
    });

    test('超过有效期的目标不再拽用户', () {
      final tracker = newTracker();
      final now = DateTime(2026, 8, 7, 12);

      tracker.remember(800, now);

      expect(tracker.consume(now.add(const Duration(seconds: 2))), isNull);
    });

    test('cancel 清空目标', () {
      final tracker = newTracker();
      final now = DateTime(2026, 8, 7, 12);

      tracker.remember(800, now);
      tracker.cancel();

      expect(tracker.hasPending, isFalse);
      expect(tracker.consume(now), isNull);
    });

    test('cancel 让已排队的帧回调作废——只清字段拦不住在途回调', () {
      final tracker = newTracker();
      final now = DateTime(2026, 8, 7, 12);
      tracker.remember(800, now);

      // 模拟排 post-frame 回调时取版本号。
      final queued = tracker.generation;
      expect(tracker.isCurrent(queued), isTrue);

      // 用户重新拖拽 / 筛选回顶。
      tracker.cancel();

      // 回调这时才执行，必须自行退出。
      expect(tracker.isCurrent(queued), isFalse);
    });

    test('没有 cancel 时排队的回调仍然有效', () {
      final tracker = newTracker();
      final now = DateTime(2026, 8, 7, 12);

      final queued = tracker.generation;
      tracker.remember(800, now);

      expect(tracker.isCurrent(queued), isTrue);
    });
  });
}
