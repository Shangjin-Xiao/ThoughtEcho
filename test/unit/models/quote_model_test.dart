/// Unit tests for Quote model
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import '../../test_harness.dart';

void main() {
  test('copyWith can explicitly clear note mode and source fields', () {
    final rich = Quote(
      id: 'note',
      content: 'text',
      date: '2026-07-15T00:00:00Z',
      sourceAuthor: 'Author',
      sourceWork: 'Work',
      editSource: 'fullscreen',
      deltaContent: '[{"insert":"text\\n"}]',
    );

    final plain = rich.copyWith(
      source: null,
      sourceAuthor: null,
      sourceWork: null,
      editSource: null,
      deltaContent: null,
    );

    expect(plain.source, isNull);
    expect(plain.editSource, isNull);
    expect(plain.deltaContent, isNull);
  });

  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('Quote Model Tests', () {
    test('should create quote with required fields', () {
      final quote = Quote(
        content: '测试内容',
        date: DateTime.now().toIso8601String(),
      );

      expect(quote.content, equals('测试内容'));
      expect(quote.date, isNotEmpty);
      expect(quote.tagIds, isEmpty);
    });

    test('should create quote with all fields', () {
      final quote = Quote(
        id: 'test-id',
        content: '测试内容带所有字段',
        date: DateTime.now().toIso8601String(),
        categoryId: 'test-category',
        tagIds: ['tag1', 'tag2'],
        location: '北京市',
        weather: '晴天',
        temperature: '25°C',
      );

      expect(quote.id, equals('test-id'));
      expect(quote.content, equals('测试内容带所有字段'));
      expect(quote.categoryId, equals('test-category'));
      expect(quote.tagIds, hasLength(2));
      expect(quote.location, equals('北京市'));
      expect(quote.weather, equals('晴天'));
      expect(quote.temperature, equals('25°C'));
    });

    test('should convert to JSON correctly', () {
      final quote = Quote(
        id: 'test-id',
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
        categoryId: 'test-category',
        tagIds: ['tag1'],
        isDeleted: true,
        deletedAt: '2024-01-02T00:00:00.000Z',
      );

      final json = quote.toJson();
      expect(json['id'], equals('test-id'));
      expect(json['content'], equals('测试内容'));
      expect(json['date'], equals('2024-01-01T00:00:00.000Z'));
      expect(json['category_id'], equals('test-category'));
      expect(json['is_deleted'], equals(1));
      expect(json['deleted_at'], equals('2024-01-02T00:00:00.000Z'));
      // tag_ids字段在toJson中被移除，因为使用关联表管理
      expect(json.containsKey('tag_ids'), isFalse);
    });

    test('should create from JSON correctly', () {
      final json = {
        'id': 'test-id',
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'category_id': 'test-category',
        'tag_ids': 'tag1,tag2',
        'is_deleted': 1,
        'deleted_at': '2024-01-02T00:00:00.000Z',
      };

      final quote = Quote.fromJson(json);
      expect(quote.id, equals('test-id'));
      expect(quote.content, equals('测试内容'));
      expect(quote.date, equals('2024-01-01T00:00:00.000Z'));
      expect(quote.categoryId, equals('test-category'));
      expect(quote.tagIds, equals(['tag1', 'tag2']));
      expect(quote.isDeleted, isTrue);
      expect(quote.deletedAt, equals('2024-01-02T00:00:00.000Z'));
    });

    test('should default soft delete fields when absent', () {
      final json = {
        'id': 'test-id',
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
      };

      final quote = Quote.fromJson(json);
      expect(quote.isDeleted, isFalse);
      expect(quote.deletedAt, isNull);
    });

    test('should normalize deletedAt to null when isDeleted is false', () {
      final quote = Quote(
        id: 'test-id',
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
        isDeleted: false,
        deletedAt: '2024-01-02T00:00:00.000Z',
      );

      expect(quote.isDeleted, isFalse);
      expect(quote.deletedAt, isNull);
      expect(quote.toJson()['deleted_at'], isNull);
    });

    test(
        'should backfill deletedAt when isDeleted is true and deletedAt is null',
        () {
      final beforeCreate = DateTime.now().toUtc();
      final quote = Quote(
        id: 'test-id',
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
        isDeleted: true,
      );
      final afterCreate = DateTime.now().toUtc();

      expect(quote.isDeleted, isTrue);
      expect(quote.deletedAt, isNotNull);

      // deletedAt should be current UTC time, not quote.date
      final deletedAtTime = DateTime.parse(quote.deletedAt!);
      expect(
        deletedAtTime
            .isAfter(beforeCreate.subtract(const Duration(seconds: 1))),
        isTrue,
        reason: 'deletedAt should be after test start time',
      );
      expect(
        deletedAtTime.isBefore(afterCreate.add(const Duration(seconds: 1))),
        isTrue,
        reason: 'deletedAt should be before test end time',
      );
    });

    test('copyWith should update soft delete fields', () {
      final base = Quote(
        id: 'test-id',
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
      );

      final updated = base.copyWith(
        isDeleted: true,
        deletedAt: '2024-01-02T00:00:00.000Z',
      );

      expect(updated.isDeleted, isTrue);
      expect(updated.deletedAt, equals('2024-01-02T00:00:00.000Z'));
    });

    test('copyWith should allow clearing deletedAt explicitly', () {
      final base = Quote(
        id: 'test-id',
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
        isDeleted: true,
        deletedAt: '2024-01-02T00:00:00.000Z',
      );

      final restored = base.copyWith(
        isDeleted: false,
        deletedAt: null,
      );

      expect(restored.isDeleted, isFalse);
      expect(restored.deletedAt, isNull);
    });

    test('copyWith should allow clearing location and weather explicitly', () {
      final base = Quote(
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
        location: '北京市',
        latitude: 39.9,
        longitude: 116.4,
        poiName: '故宫博物院',
        weather: 'clear',
        temperature: '25°C',
      );

      final updated = base.copyWith(
        location: null,
        latitude: null,
        longitude: null,
        poiName: null,
        weather: null,
        temperature: null,
      );

      expect(updated.location, isNull);
      expect(updated.latitude, isNull);
      expect(updated.longitude, isNull);
      expect(updated.poiName, isNull);
      expect(updated.weather, isNull);
      expect(updated.temperature, isNull);
    });

    test('should validate data correctly', () {
      // 测试有效数据
      expect(Quote.isValidContent('有效内容'), isTrue);
      expect(Quote.isValidDate('2024-01-01T00:00:00.000Z'), isTrue);
      expect(Quote.isValidColorHex('#FF0000'), isTrue);
      expect(Quote.isValidColorHex(null), isTrue);

      // 测试无效数据
      expect(Quote.isValidContent(''), isFalse);
      expect(Quote.isValidContent('a' * 10001), isFalse);
      expect(Quote.isValidDate('invalid-date'), isFalse);
      expect(Quote.isValidColorHex('invalid-color'), isFalse);
      expect(Quote.isValidColorHex('#ZZ0000'), isFalse);
    });

    test(
        'safeDeltaOps should handle malformed and non-Map delta items gracefully without throwing TypeError',
        () {
      final quote = Quote(
        id: 'test-malformed-delta',
        content: '回退文本内容\n',
        date: '2026-08-23T09:00:00.000',
        deltaContent: '[123, null, "invalid string", {"insert": "正常文本\\n"}]',
      );

      final ops = quote.safeDeltaOps;
      expect(ops, isNotEmpty);
      expect(ops.first['insert'], equals('正常文本\n'));
    });

    test('safeDeltaOps should handle non-string keys in delta JSON maps', () {
      final quote = Quote(
        id: 'test-non-string-key',
        content: '回退文本\n',
        date: '2026-08-23T09:00:00.000',
        deltaContent: '[{"insert": "测试\\n"}]',
      );

      final ops = quote.safeDeltaOps;
      expect(ops, isNotEmpty);
      expect(ops.first['insert'], equals('测试\n'));
    });

    test('should handle edge cases in fromJson', () {
      // 测试空tag_ids
      final json1 = {
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'tag_ids': '',
      };
      final quote1 = Quote.fromJson(json1);
      expect(quote1.tagIds, isEmpty);

      // 测试null keywords
      final json2 = {
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'keywords': null,
      };
      final quote2 = Quote.fromJson(json2);
      expect(quote2.keywords, isNull);

      // 测试数组格式的tag_ids
      final json3 = {
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'tag_ids': ['tag1', 'tag2'],
      };
      final quote3 = Quote.fromJson(json3);
      expect(quote3.tagIds, equals(['tag1', 'tag2']));
    });

    test('should throw error for invalid JSON', () {
      // 测试缺少必填字段
      expect(() => Quote.fromJson({}), throwsA(isA<ArgumentError>()));
      expect(
        () => Quote.fromJson({'content': ''}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => Quote.fromJson({'content': '测试', 'date': ''}),
        throwsA(isA<ArgumentError>()),
      );

      // 测试无效日期格式
      expect(
        () => Quote.fromJson({'content': '测试内容', 'date': 'invalid-date'}),
        throwsA(isA<ArgumentError>()),
      );

      // 测试无效颜色格式
      expect(
        () => Quote.fromJson({
          'content': '测试内容',
          'date': '2024-01-01T00:00:00.000Z',
          'color_hex': 'invalid-color',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

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
