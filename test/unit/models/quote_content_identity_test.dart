import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

/// `Quote.operator ==` 只比 id，回答不了「这一行变了没有」。列表侧靠
/// [Quote.hasSameContentAs] 决定能不能沿用旧实例 —— 判错一次的后果是卡片
/// **永远停在旧内容上**，所以每一个会被卡片画出来的字段都要能把它判成「变了」。
Quote _quote({
  String? content,
  List<String>? tagIds,
  String? colorHex,
  String? deltaContent,
  int? favoriteCount,
  String? lastModified,
  String? weather,
  String? sourceAuthor,
  bool? isDeleted,
}) =>
    Quote(
      id: 'q-1',
      content: content ?? '原始正文',
      date: '2026-08-23T09:00:00.000',
      tagIds: tagIds ?? const ['tag-a'],
      colorHex: colorHex,
      deltaContent: deltaContent,
      favoriteCount: favoriteCount ?? 0,
      lastModified: lastModified,
      weather: weather,
      sourceAuthor: sourceAuthor,
      isDeleted: isDeleted ?? false,
    );

void main() {
  group('Quote.hasSameContentAs', () {
    test('同一实例、以及逐字段相同的两个实例都算没变', () {
      final quote = _quote();
      expect(quote.hasSameContentAs(quote), isTrue);
      expect(_quote().hasSameContentAs(_quote()), isTrue);
    });

    test('id 不同直接算变了', () {
      final other = Quote(
        id: 'q-2',
        content: '原始正文',
        date: '2026-08-23T09:00:00.000',
        tagIds: const ['tag-a'],
      );
      expect(_quote().hasSameContentAs(other), isFalse);
    });

    // 卡片上画得出来的字段逐个过一遍：漏掉任何一个都会让那一处的改动
    // 悄悄不刷新。
    final cases = <String, Quote Function()>{
      '正文': () => _quote(content: '改过的正文'),
      '标签': () => _quote(tagIds: const ['tag-a', 'tag-b']),
      '标签换了一个': () => _quote(tagIds: const ['tag-b']),
      '卡片颜色': () => _quote(colorHex: '#FF0000'),
      '富文本内容': () => _quote(deltaContent: '[{"insert":"x\\n"}]'),
      '收藏次数': () => _quote(favoriteCount: 3),
      '编辑时间': () => _quote(lastModified: '2026-08-23T10:00:00.000'),
      '天气': () => _quote(weather: 'sunny'),
      '出处作者': () => _quote(sourceAuthor: '某人'),
      '回收站标记': () => _quote(isDeleted: true),
    };
    for (final entry in cases.entries) {
      test('${entry.key}变了就必须算变了', () {
        expect(_quote().hasSameContentAs(entry.value()), isFalse);
        expect(entry.value().hasSameContentAs(_quote()), isFalse);
      });
    }

    test('== 只比 id，不能拿来当「没变」的判据', () {
      final edited = _quote(content: '改过的正文');
      expect(_quote() == edited, isTrue, reason: '这正是 == 不能用的原因');
      expect(_quote().hasSameContentAs(edited), isFalse);
    });
  });
}
