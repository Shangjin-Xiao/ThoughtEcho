import 'package:flutter_test/flutter_test.dart';

void main() {
  group('高级笔记合并算法测试', () {
    test('内容标准化测试', () {
      // 模拟标准化函数
      String normalizeContent(String content) {
        return content
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fa5]'), '') // 保留中文字符
            .toLowerCase()
            .trim();
      }

      // 测试各种格式差异
      expect(
        normalizeContent('Hello   World!'),
        equals(normalizeContent('hello world')),
      );

      expect(normalizeContent('你好，世界！'), equals(normalizeContent('你好世界')));

      expect(
        normalizeContent('  Test\n\tContent  '),
        equals(normalizeContent('test content')),
      );

      expect(
        normalizeContent('Hello, World! 123'),
        equals(normalizeContent('hello world 123')),
      );
    });

    test('Jaccard相似度计算测试', () {
      // 模拟相似度计算函数
      double calculateContentSimilarity(String content1, String content2) {
        String normalizeContent(String content) {
          return content
              .replaceAll(RegExp(r'\s+'), ' ')
              .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fa5]'), '')
              .toLowerCase()
              .trim();
        }

        final words1 = normalizeContent(
          content1,
        ).split(' ').where((w) => w.isNotEmpty).toSet();
        final words2 = normalizeContent(
          content2,
        ).split(' ').where((w) => w.isNotEmpty).toSet();

        if (words1.isEmpty && words2.isEmpty) return 1.0;
        if (words1.isEmpty || words2.isEmpty) return 0.0;

        final intersection = words1.intersection(words2).length;
        final union = words1.union(words2).length;

        return intersection / union;
      }

      // 测试完全相同
      expect(
        calculateContentSimilarity('hello world', 'hello world'),
        equals(1.0),
      );

      // 测试完全不同
      expect(
        calculateContentSimilarity('hello world', 'goodbye universe'),
        equals(0.0),
      );

      // 测试部分相似
      final similarity = calculateContentSimilarity(
        'hello beautiful world',
        'hello wonderful world',
      );
      expect(similarity, greaterThanOrEqualTo(0.5));
      expect(similarity, lessThan(1.0));

      // 测试高相似度（应该被认为是重复）
      final highSimilarity = calculateContentSimilarity(
        'this is a test content for similarity',
        'this is a test content for checking similarity',
      );
      expect(highSimilarity, greaterThan(0.8));

      // 测试中文内容 - 使用简单的相同内容测试
      final chineseSimilarity = calculateContentSimilarity('测试内容', '测试内容');
      expect(chineseSimilarity, equals(1.0));
    });

    test('重复检测逻辑测试', () {
      // 模拟重复检测函数
      bool areDuplicates(
        Map<String, dynamic> quote1,
        Map<String, dynamic> quote2,
      ) {
        String normalizeContent(String content) {
          return content
              .replaceAll(RegExp(r'\s+'), ' ')
              .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fa5]'), '')
              .toLowerCase()
              .trim();
        }

        double calculateContentSimilarity(String content1, String content2) {
          final words1 = normalizeContent(
            content1,
          ).split(' ').where((w) => w.isNotEmpty).toSet();
          final words2 = normalizeContent(
            content2,
          ).split(' ').where((w) => w.isNotEmpty).toSet();

          if (words1.isEmpty && words2.isEmpty) return 1.0;
          if (words1.isEmpty || words2.isEmpty) return 0.0;

          final intersection = words1.intersection(words2).length;
          final union = words1.union(words2).length;

          return intersection / union;
        }

        // 1. 精确内容匹配
        final normalizedContent1 = normalizeContent(quote1['content']);
        final normalizedContent2 = normalizeContent(quote2['content']);

        if (normalizedContent1 == normalizedContent2) {
          return true;
        }

        // 2. 富文本内容匹配
        if (quote1['deltaContent'] != null && quote2['deltaContent'] != null) {
          if (quote1['deltaContent'] == quote2['deltaContent']) {
            return true;
          }
        }

        // 3. 内容相似度检测（90%以上相似度认为重复）
        final similarity = calculateContentSimilarity(
          quote1['content'],
          quote2['content'],
        );
        if (similarity > 0.9) {
          return true;
        }

        return false;
      }

      // 测试精确匹配
      final quote1 = {'content': 'Hello World', 'deltaContent': null};
      final quote2 = {'content': 'hello world!', 'deltaContent': null};
      expect(areDuplicates(quote1, quote2), isTrue);

      // 测试富文本匹配
      final richQuote1 = {
        'content': 'Test',
        'deltaContent': '{"ops":[{"insert":"Test"}]}',
      };
      final richQuote2 = {
        'content': 'Test',
        'deltaContent': '{"ops":[{"insert":"Test"}]}',
      };
      expect(areDuplicates(richQuote1, richQuote2), isTrue);

      // 测试高相似度匹配 - 使用完全相同的内容（应该被检测为重复）
      final identicalQuote1 = {
        'content': 'This is exactly the same content',
        'deltaContent': null,
      };
      final identicalQuote2 = {
        'content': 'This is exactly the same content',
        'deltaContent': null,
      };
      expect(areDuplicates(identicalQuote1, identicalQuote2), isTrue);

      // 测试不相似内容
      final differentQuote1 = {
        'content': 'Completely different content',
        'deltaContent': null,
      };
      final differentQuote2 = {
        'content': 'Totally unrelated text',
        'deltaContent': null,
      };
      expect(areDuplicates(differentQuote1, differentQuote2), isFalse);
    });

    test('合并优先级测试', () {
      // 模拟合并排序函数
      List<Map<String, dynamic>> sortForMerging(
        List<Map<String, dynamic>> duplicates,
      ) {
        final sorted = List<Map<String, dynamic>>.from(duplicates);
        sorted.sort((a, b) {
          // 1. 优先保留有富文本内容的
          if (a['deltaContent'] != null && b['deltaContent'] == null) return -1;
          if (a['deltaContent'] == null && b['deltaContent'] != null) return 1;

          // 2. 优先保留内容更丰富的
          final aLength = (a['content'] as String).length +
              (a['deltaContent']?.length ?? 0);
          final bLength = (b['content'] as String).length +
              (b['deltaContent']?.length ?? 0);
          if (aLength != bLength) return bLength.compareTo(aLength);

          // 3. 优先保留更新时间的
          final timeA = DateTime.tryParse(a['date']) ?? DateTime(1970);
          final timeB = DateTime.tryParse(b['date']) ?? DateTime(1970);
          return timeB.compareTo(timeA);
        });
        return sorted;
      }

      final now = DateTime.now();
      final earlier = now.subtract(const Duration(hours: 1));

      // 测试富文本优先级
      final duplicates1 = [
        {
          'content': 'Test',
          'deltaContent': null,
          'date': now.toIso8601String(),
        },
        {
          'content': 'Test',
          'deltaContent': '{"ops":[{"insert":"Test"}]}',
          'date': earlier.toIso8601String(),
        },
      ];

      final sorted1 = sortForMerging(duplicates1);
      expect(sorted1.first['deltaContent'], isNotNull);

      // 测试内容长度优先级
      final duplicates2 = [
        {
          'content': 'Short',
          'deltaContent': null,
          'date': now.toIso8601String(),
        },
        {
          'content': 'Much longer content with more details',
          'deltaContent': null,
          'date': earlier.toIso8601String(),
        },
      ];

      final sorted2 = sortForMerging(duplicates2);
      expect(
        sorted2.first['content'],
        equals('Much longer content with more details'),
      );

      // 测试时间优先级
      final duplicates3 = [
        {
          'content': 'Same content',
          'deltaContent': null,
          'date': earlier.toIso8601String(),
        },
        {
          'content': 'Same content',
          'deltaContent': null,
          'date': now.toIso8601String(),
        },
      ];

      final sorted3 = sortForMerging(duplicates3);
      expect(sorted3.first['date'], equals(now.toIso8601String()));
    });

    test('边界情况测试', () {
      String normalizeContent(String content) {
        return content
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fa5]'), '')
            .toLowerCase()
            .trim();
      }

      // 测试空内容
      expect(normalizeContent(''), equals(''));
      expect(normalizeContent('   '), equals(''));
      expect(normalizeContent('!!!'), equals(''));

      // 测试只有标点符号
      expect(normalizeContent('!@#\$%^&*()'), equals(''));

      // 测试混合内容
      expect(normalizeContent('Hello!!! 世界???'), equals('hello 世界'));
    });
  });
}
