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

    final t0 = DateTime(2026, 8, 7, 12);

    test('记住的目标在有效期内可以反复读取', () {
      final tracker = newTracker();

      tracker.remember(800, t0);
      expect(tracker.hasPending, isTrue);
      expect(tracker.peek(t0.add(const Duration(milliseconds: 500))), 800);
      // peek 不清空：调用方按决策结果再决定 remember 还是 clear。
      expect(tracker.peek(t0.add(const Duration(milliseconds: 900))), 800);
    });

    test('超过有效期的目标不再拽用户，并就地丢弃', () {
      final tracker = newTracker();

      tracker.remember(800, t0);

      expect(tracker.peek(t0.add(const Duration(seconds: 2))), isNull);
      expect(tracker.hasPending, isFalse);
    });

    test('同一目标反复顺延时保留最初时刻，有效期不会被无限续期', () {
      final tracker = newTracker();

      // 数据事件一个接一个地来，每次都重新挂起同一个目标。
      tracker.remember(800, t0);
      tracker.remember(800, t0.add(const Duration(milliseconds: 600)));
      tracker.remember(800, t0.add(const Duration(milliseconds: 1200)));

      // 若每次都重新计时，这里还在有效期内，用户会在很久后被忽然拽回去。
      expect(tracker.peek(t0.add(const Duration(milliseconds: 1600))), isNull);
    });

    test('同一轮夹紧里目标越记越深也不重新计时', () {
      final tracker = newTracker();

      // 内容一次比一次短，挂起的目标随之变深，但仍是同一轮夹紧。
      tracker.remember(800, t0);
      tracker.remember(1200, t0.add(const Duration(milliseconds: 700)));
      tracker.remember(1500, t0.add(const Duration(milliseconds: 1400)));

      // 计时从第一次挂起算起，到这里已经超时。
      expect(tracker.peek(t0.add(const Duration(milliseconds: 1600))), isNull);
    });

    test('过期之后本轮夹紧彻底作废，同一次决策里不能换个目标重新计时', () {
      final tracker = newTracker();

      tracker.remember(800, t0);

      // peek 判定过期。紧接着决策又拿仍被夹紧的 previousOffset 来挂新目标 ——
      // 这正是"有效期被无限续期"的入口，必须挡住。
      final now = t0.add(const Duration(seconds: 2));
      expect(tracker.peek(now), isNull);
      expect(tracker.isExpired, isTrue);
      expect(tracker.remember(1200, now), isFalse);
      expect(tracker.hasPending, isFalse);
      expect(tracker.peek(now), isNull);
    });

    test('连续刷新超过有效期后不再挂起，直到一次「无需还原」的事件翻篇', () {
      final tracker = newTracker();
      var now = t0;

      tracker.remember(800, now);

      // 数据事件每 300ms 来一次，每次都想挂起一个（可能更深的）目标。
      var pending = 800.0;
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 300));
        tracker.peek(now);
        pending += 10;
        tracker.remember(pending, now);
      }

      // 无论刷新多密集，1.5s 之后都不该还剩下任何待还原目标。
      expect(tracker.peek(now), isNull);
      expect(tracker.hasPending, isFalse);

      // 列表恢复正常（决策为 none → clear）后才重新开张。
      tracker.clear();
      expect(tracker.isExpired, isFalse);
      expect(tracker.remember(900, now), isTrue);
      expect(tracker.peek(now.add(const Duration(milliseconds: 500))), 900);
    });

    test('cancel 同样解除过期封锁', () {
      final tracker = newTracker();

      tracker.remember(800, t0);
      final now = t0.add(const Duration(seconds: 2));
      expect(tracker.peek(now), isNull);

      tracker.cancel();

      expect(tracker.isExpired, isFalse);
      expect(tracker.remember(1200, now), isTrue);
      expect(tracker.peek(now.add(const Duration(milliseconds: 500))), 1200);
    });

    test('clear 清空目标但不影响版本号', () {
      final tracker = newTracker();
      final queued = tracker.generation;

      tracker.remember(800, t0);
      tracker.clear();

      expect(tracker.hasPending, isFalse);
      expect(tracker.isCurrent(queued), isTrue);
    });

    test('cancel 让已排队的帧回调作废——只清字段拦不住在途回调', () {
      final tracker = newTracker();
      tracker.remember(800, t0);

      // 模拟排 post-frame 回调时取版本号。
      final queued = tracker.generation;
      expect(tracker.isCurrent(queued), isTrue);

      // 用户重新拖拽 / 筛选回顶。
      tracker.cancel();

      // 回调这时才执行，必须自行退出。
      expect(tracker.isCurrent(queued), isFalse);
      expect(tracker.hasPending, isFalse);
    });
  });
}
