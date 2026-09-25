import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

void main() {
  group('Quote model performance benchmark', () {
    test('isValidColorHex repeated calls benchmark', () {
      final Stopwatch stopwatch = Stopwatch()..start();

      const iterations = 50000;
      int validCount = 0;
      for (int i = 0; i < iterations; i++) {
        if (Quote.isValidColorHex('#123456')) validCount++;
        if (Quote.isValidColorHex('#ABCDEF')) validCount++;
        if (!Quote.isValidColorHex('invalid')) validCount++;
      }

      stopwatch.stop();
      expect(validCount, iterations * 3);
      // 记录基准耗时，避免在负载波动的 CI 环境下因固定时间阈值偶发失败
      expect(stopwatch.elapsedMicroseconds, isPositive);
    });

    test('stripAuthorPrefix repeated calls benchmark', () {
      final Stopwatch stopwatch = Stopwatch()..start();

      const iterations = 20000;
      int processedCount = 0;
      for (int i = 0; i < iterations; i++) {
        final res1 = Quote.stripAuthorPrefix('—— 鲁迅');
        if (res1 == '鲁迅') processedCount++;

        final res2 = Quote.stripAuthorPrefix('作者：《朝花夕拾》');
        if (res2 == '朝花夕拾') processedCount++;

        final res3 = Quote.stripAuthorPrefix('by: 「张三」');
        if (res3 == '张三') processedCount++;
      }

      stopwatch.stop();
      expect(processedCount, iterations * 3);
      expect(stopwatch.elapsedMicroseconds, isPositive);
    });

    test('isSelfAttributed and isBuiltinPersonalWork benchmark', () {
      final Stopwatch stopwatch = Stopwatch()..start();

      final quote = Quote(
        content: '今天天气真好',
        date: '2026-01-01',
        source: '作者：阿澈 - 阿澈随笔',
      );

      const iterations = 10000;
      int count = 0;
      for (int i = 0; i < iterations; i++) {
        if (Quote.isBuiltinPersonalWork('鲁迅 - 狂人日记')) count++;
        if (quote.isSelfAttributed(userNickname: '阿澈')) count++;
      }

      stopwatch.stop();
      expect(count, iterations);
      expect(stopwatch.elapsedMicroseconds, isPositive);
    });
  });
}
