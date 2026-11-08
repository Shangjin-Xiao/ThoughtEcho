import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

const Set<String> coveredPersistentKeysInHasSameContentAs = {
  'id',
  'content',
  'date',
  'ai_analysis',
  'source',
  'source_author',
  'source_work',
  'sentiment',
  'keywords',
  'summary',
  'category_id',
  'color_hex',
  'location',
  'latitude',
  'longitude',
  'poi_name',
  'weather',
  'temperature',
  'edit_source',
  'delta_content',
  'day_period',
  'last_modified',
  'favorite_count',
  'is_deleted',
  'deleted_at',
};

Quote _createFullyPopulatedQuote({
  String id = 'quote-test-1',
  String content = '示例笔记正文',
  String date = '2026-11-08T00:00:00.000Z',
  String? source = 'MockSource',
  String? sourceAuthor = 'MockAuthor',
  String? sourceWork = 'MockWork',
  List<String> tagIds = const ['tag-1', 'tag-2'],
  String? aiAnalysis = 'MockAIAnalysis',
  String? sentiment = 'positive',
  List<String>? keywords = const ['kw1', 'kw2'],
  String? summary = 'MockSummary',
  String? categoryId = 'cat-1',
  String? colorHex = '#123456',
  String? location = '示例省·示例市',
  double? latitude = 39.9042,
  double? longitude = 116.4074,
  String? poiName = 'MockPOI',
  String? weather = '晴',
  String? temperature = '22°C',
  String? editSource = 'fullscreen',
  String? deltaContent = '[{"insert":"示例富文本\\n"}]',
  String? dayPeriod = 'morning',
  String? lastModified = '2026-11-08T00:30:00.000Z',
  int favoriteCount = 7,
  bool isDeleted = true,
  String? deletedAt = '2026-11-08T00:30:00.000Z',
}) {
  return Quote(
    id: id,
    content: content,
    date: date,
    source: source,
    sourceAuthor: sourceAuthor,
    sourceWork: sourceWork,
    tagIds: tagIds,
    aiAnalysis: aiAnalysis,
    sentiment: sentiment,
    keywords: keywords,
    summary: summary,
    categoryId: categoryId,
    colorHex: colorHex,
    location: location,
    latitude: latitude,
    longitude: longitude,
    poiName: poiName,
    weather: weather,
    temperature: temperature,
    editSource: editSource,
    deltaContent: deltaContent,
    dayPeriod: dayPeriod,
    lastModified: lastModified,
    favoriteCount: favoriteCount,
    isDeleted: isDeleted,
    deletedAt: deletedAt,
  );
}

void main() {
  group('Quote.hasSameContentAs 持久化字段守卫测试', () {
    test(
        'toJson() 生成的所有键必须与 coveredPersistentKeysInHasSameContentAs 严格一致且不含 tag_ids',
        () {
      final quote = _createFullyPopulatedQuote();

      // 验证 toJson 生成的所有持久化键集合
      expect(quote.toJson().keys.toSet(),
          equals(coveredPersistentKeysInHasSameContentAs));
      // 验证 tag_ids 通过独立关联表管理，不直接进入 toJson
      expect(quote.toJson().containsKey('tag_ids'), isFalse);
    });

    test('同一实例或所有字段等价的两个实例判定未变 (返回 true)', () {
      final q1 = _createFullyPopulatedQuote();
      final q2 = _createFullyPopulatedQuote();

      expect(q1.hasSameContentAs(q1), isTrue);
      expect(q1.hasSameContentAs(q2), isTrue);
    });

    test('任一持久化字段产生差异时 hasSameContentAs 均必须返回 false', () {
      final base = _createFullyPopulatedQuote();

      final diffCases = <String, Quote>{
        'id': base.copyWith(id: 'diff-id'),
        'content': base.copyWith(content: '不同的笔记正文'),
        'date': base.copyWith(date: '2026-11-09T00:00:00.000Z'),
        'ai_analysis': base.copyWith(aiAnalysis: '不同AI分析'),
        'source_author': base.copyWith(sourceAuthor: '不同作者'),
        'source_work': base.copyWith(sourceWork: '不同作品'),
        'sentiment': base.copyWith(sentiment: 'negative'),
        'keywords': base.copyWith(keywords: ['diff-kw']),
        'summary': base.copyWith(summary: '不同摘要'),
        'category_id': base.copyWith(categoryId: 'diff-cat'),
        'color_hex': base.copyWith(colorHex: '#654321'),
        'location': base.copyWith(location: '示例省·其他市'),
        'latitude': base.copyWith(latitude: 31.2304),
        'longitude': base.copyWith(longitude: 121.4737),
        'poi_name': base.copyWith(poiName: 'MockOtherPOI'),
        'weather': base.copyWith(weather: '多云'),
        'temperature': base.copyWith(temperature: '18°C'),
        'edit_source': base.copyWith(editSource: 'dialog'),
        'delta_content': base.copyWith(deltaContent: '[{"insert":"其他富文本\\n"}]'),
        'day_period': base.copyWith(dayPeriod: 'night'),
        'last_modified':
            base.copyWith(lastModified: '2026-11-09T01:00:00.000Z'),
        'favorite_count': base.copyWith(favoriteCount: 99),
        'is_deleted': base.copyWith(isDeleted: false),
        'deleted_at': base.copyWith(deletedAt: '2026-11-09T02:00:00.000Z'),
      };

      for (final entry in diffCases.entries) {
        expect(
          base.hasSameContentAs(entry.value),
          isFalse,
          reason: '字段 ${entry.key} 发生变化时 hasSameContentAs 必须返回 false',
        );
        expect(
          entry.value.hasSameContentAs(base),
          isFalse,
          reason: '字段 ${entry.key} 对称比对时 hasSameContentAs 也必须返回 false',
        );
      }
    });

    test('无派生作者作品时，底层 _source 字段发生差异时 hasSameContentAs 返回 false', () {
      final qSourceA = _createFullyPopulatedQuote(
        sourceAuthor: null,
        sourceWork: null,
        source: 'MockSourceA',
      );
      final qSourceB = _createFullyPopulatedQuote(
        sourceAuthor: null,
        sourceWork: null,
        source: 'MockSourceB',
      );

      expect(qSourceA.hasSameContentAs(qSourceB), isFalse);
      expect(qSourceB.hasSameContentAs(qSourceA), isFalse);
    });

    test('关联表管理的 tagIds 产生差异时 hasSameContentAs 必须返回 false', () {
      final base = _createFullyPopulatedQuote();
      final diffTagIds = base.copyWith(tagIds: ['different-tag']);

      expect(base.hasSameContentAs(diffTagIds), isFalse);
      expect(diffTagIds.hasSameContentAs(base), isFalse);
    });
  });
}
