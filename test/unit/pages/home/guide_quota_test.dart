import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/pages/home/guide_quota.dart';

void main() {
  group('GuideQuota', () {
    test('一开始就可用', () {
      expect(GuideQuota().isAvailable, isTrue);
    });

    test('同一次进入页面里弹过一个之后就不再可用', () {
      final quota = GuideQuota()..onPageChanged(1);

      quota.consume();

      expect(quota.isAvailable, isFalse);
    });

    test('停在同一页上反复触发不会刷新名额', () {
      final quota = GuideQuota()..onPageChanged(1);
      quota.consume();

      // 列表加载完、目标就位等都会再次触发同一页。
      quota.onPageChanged(1);

      expect(quota.isAvailable, isFalse);
    });

    test('切到别的页面重新给一个名额', () {
      final quota = GuideQuota()..onPageChanged(1);
      quota.consume();

      quota.onPageChanged(3);

      expect(quota.isAvailable, isTrue);
    });

    test('会话总数用满后，换页也不再可用', () {
      final quota = GuideQuota(sessionQuota: 2);

      quota.onPageChanged(0);
      quota.consume();
      quota.onPageChanged(1);
      quota.consume();
      quota.onPageChanged(3);

      expect(quota.sessionShown, 2);
      expect(quota.isAvailable, isFalse);
    });

    test('没弹出来就不记账', () {
      final quota = GuideQuota()..onPageChanged(1);

      // 目标没渲染出来时 show() 返回 false，调用方不该调 consume()。
      expect(quota.sessionShown, 0);
      expect(quota.isAvailable, isTrue);
    });
  });
}
