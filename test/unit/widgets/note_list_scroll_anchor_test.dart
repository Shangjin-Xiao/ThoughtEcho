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
}
