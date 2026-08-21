import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/anniversary_display_utils.dart';

void main() {
  group('AnniversaryDisplayUtils', () {
    test('每一届的展示期都从上线日推导', () {
      final first = AnniversaryDisplayUtils.editionForYear(1);
      expect(first.start, DateTime(2026, 3, 23));
      expect(first.endExclusive, DateTime(2026, 5, 1));
      expect(first.rangeLabel, '2025.3.23 - 2026.3.23');

      final second = AnniversaryDisplayUtils.editionForYear(2);
      expect(second.start, DateTime(2027, 3, 23));
      expect(second.endExclusive, DateTime(2027, 5, 1));
      expect(second.rangeLabel, '2025.3.23 - 2027.3.23');
    });

    test('currentEdition 在窗口内返回对应届数', () {
      expect(
        AnniversaryDisplayUtils.currentEdition(DateTime(2026, 3, 23))?.year,
        1,
      );
      expect(
        AnniversaryDisplayUtils.currentEdition(
          DateTime(2027, 4, 30, 23, 59, 59),
        )?.year,
        2,
      );
    });

    test('currentEdition 在窗口外返回 null', () {
      expect(
        AnniversaryDisplayUtils.currentEdition(
          DateTime(2026, 3, 22, 23, 59, 59),
        ),
        isNull,
      );
      expect(
        AnniversaryDisplayUtils.currentEdition(DateTime(2026, 5, 1)),
        isNull,
      );
      // 上线当年还没到第一个周年。
      expect(
        AnniversaryDisplayUtils.currentEdition(DateTime(2025, 4, 1)),
        isNull,
      );
    });

    test('nextEditionYear 给出当届或下一届', () {
      // 上线当年还没有任何一届，先按一周年算。
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2025, 4, 1)), 1);
      // 一周年展示期开始前和进行中都还是这一届。
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2026, 1, 5)), 1);
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2026, 3, 23)), 1);
      // 一周年展示期结束后顺延到两周年。
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2026, 5, 1)), 2);
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2026, 8, 21)), 2);
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2027, 4, 1)), 2);
      expect(AnniversaryDisplayUtils.nextEditionYear(DateTime(2027, 6, 1)), 3);
    });

    test('模拟届数无视真实日期', () {
      expect(
        AnniversaryDisplayUtils.currentEdition(
          DateTime(2026, 8, 15),
          simulatedYear: 2,
        )?.year,
        2,
      );
      expect(
        AnniversaryDisplayUtils.shouldShowSettingsBanner(
          now: DateTime(2026, 8, 15),
        ),
        isFalse,
      );
      expect(
        AnniversaryDisplayUtils.shouldShowSettingsBanner(
          now: DateTime(2026, 8, 15),
          simulatedYear: 2,
        ),
        isTrue,
      );
    });

    test('每一届各自只自动播放一次', () {
      expect(
        AnniversaryDisplayUtils.shouldAutoShowAnimation(
          now: DateTime(2027, 3, 25),
          shownYears: const [1],
          anniversaryAnimationEnabled: true,
        ),
        isTrue,
      );
      expect(
        AnniversaryDisplayUtils.shouldAutoShowAnimation(
          now: DateTime(2027, 3, 25),
          shownYears: const [1, 2],
          anniversaryAnimationEnabled: true,
        ),
        isFalse,
      );
      expect(
        AnniversaryDisplayUtils.shouldAutoShowAnimation(
          now: DateTime(2027, 3, 25),
          shownYears: const [],
          anniversaryAnimationEnabled: false,
        ),
        isFalse,
      );
      expect(
        AnniversaryDisplayUtils.shouldAutoShowAnimation(
          now: DateTime(2026, 8, 15),
          shownYears: const [],
          anniversaryAnimationEnabled: true,
        ),
        isFalse,
      );
      expect(
        AnniversaryDisplayUtils.shouldAutoShowAnimation(
          now: DateTime(2026, 8, 15),
          shownYears: const [1],
          anniversaryAnimationEnabled: true,
          simulatedYear: 2,
        ),
        isTrue,
      );
    });

    test('老用户标记只认更早的届数', () {
      expect(
        AnniversaryDisplayUtils.hasEarlierEdition(
          shownYears: const [1],
          currentYear: 2,
        ),
        isTrue,
      );
      expect(
        AnniversaryDisplayUtils.hasEarlierEdition(
          shownYears: const [2],
          currentYear: 2,
        ),
        isFalse,
      );
      expect(AnniversaryDisplayUtils.earliestShownYear(const [2, 1]), 1);
      expect(AnniversaryDisplayUtils.earliestShownYear(const []), isNull);
    });
  });
}
