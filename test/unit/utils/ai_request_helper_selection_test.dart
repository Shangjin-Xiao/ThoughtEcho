import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/ai_request_helper.dart';

Quote note(String id, String date, {int length = 10}) => Quote(
      id: id,
      content: 'x' * length,
      date: date,
    );

void main() {
  final helper = AIRequestHelper();

  group('selectQuotesForAnalysis', () {
    test('条数没超上限时全部保留，并按时间正序交出', () {
      final quotes = [
        note('b', '2026-08-02T10:00:00'),
        note('a', '2026-08-01T10:00:00'),
        note('c', '2026-08-03T10:00:00'),
      ];

      final selected = helper.selectQuotesForAnalysis(quotes);

      // 挑的时候倒序（先要最近的），交给模型时正序（顺着读才看得出变化）
      expect(selected.map((q) => q.id).toList(), ['a', 'b', 'c']);
    });

    test('超过条数上限时留下最近的那一批', () {
      final quotes = List.generate(
        AIRequestHelper.maxQuotesForAnalysis + 50,
        (i) => note(
          'n$i',
          DateTime(2026, 1, 1).add(Duration(days: i)).toIso8601String(),
        ),
      );

      final selected = helper.selectQuotesForAnalysis(quotes);

      expect(selected.length, AIRequestHelper.maxQuotesForAnalysis);
      // 最后一条一定是最新的那条
      expect(selected.last.id, 'n${quotes.length - 1}');
      // 最早的那批被丢掉
      expect(selected.any((q) => q.id == 'n0'), false);
    });

    test('总字数超预算时提前收手', () {
      final quotes = List.generate(
        30,
        (i) => note(
          'n$i',
          DateTime(2026, 1, 1).add(Duration(days: i)).toIso8601String(),
          length: AIRequestHelper.maxCharsPerQuote,
        ),
      );

      final selected = helper.selectQuotesForAnalysis(quotes);
      final total = selected.fold<int>(0, (sum, q) => sum + q.content.length);

      expect(total <= AIRequestHelper.maxContentCharsForAnalysis, true);
      expect(selected.length < quotes.length, true);
    });

    test('单条超长笔记不会撑爆总预算', () {
      final huge = note(
        'huge',
        '2026-01-01T00:00:00',
        length: AIRequestHelper.maxContentCharsForAnalysis * 3,
      );

      final selected = helper.selectQuotesForAnalysis([huge]);

      // 唯一一条要留下，但正文送出去之前会被截短
      expect(selected.length, 1);
      final json = helper.convertQuotesToJson(selected);
      final content = (json['quotes'] as List).first['content'] as String;
      expect(
        content.length <= AIRequestHelper.maxCharsPerQuote + 8,
        true,
        reason: '截断标记之外不该再有多余正文',
      );
      expect(json['metadata']['truncated'], true);
    });
  });

  group('convertQuotesToJson', () {
    test('没截断时 truncated 为 false，且不送 id', () {
      final json = helper.convertQuotesToJson([
        note('a', '2026-08-01T10:00:00'),
      ]);

      expect(json['metadata']['truncated'], false);
      expect(json['metadata']['totalQuotes'], 1);
      expect((json['quotes'] as List).first.containsKey('id'), false);
    });
  });
}
