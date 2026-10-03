import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/generated_card.dart';
import 'package:thoughtecho/constants/card_templates.dart';

void main() {
  group('AI卡片保存功能测试', () {
    test('知识卡片SVG生成和图片转换', () async {
      // 生成知识卡片SVG
      final svgContent = CardTemplates.knowledgeTemplate(
        content: '今天学习了Flutter的状态管理，发现Provider模式非常实用，可以有效地管理应用状态。',
        author: '张三',
        date: '2024年1月15日',
      );

      expect(svgContent, isNotNull);
      expect(svgContent, contains('<svg'));
      expect(svgContent, contains('</svg>'));
      expect(svgContent, contains('心迹'));

      // 创建GeneratedCard
      final card = GeneratedCard(
        id: 'test_card_1',
        noteId: 'note_1',
        originalContent: '今天学习了Flutter的状态管理，发现Provider模式非常实用，可以有效地管理应用状态。',
        svgContent: svgContent,
        type: CardType.knowledge,
        createdAt: DateTime.now(),
      );

      // 转换为图片
      final imageBytes = await card.toImageBytes();

      expect(imageBytes, isNotNull);
      expect(imageBytes, isA<Uint8List>());
      expect(imageBytes.length, greaterThan(0));

      // 检查PNG文件头
      expect(imageBytes[0], equals(0x89));
      expect(imageBytes[1], equals(0x50));
      expect(imageBytes[2], equals(0x4E));
      expect(imageBytes[3], equals(0x47));

      // Test output: 知识卡片图片大小: ${imageBytes.length} bytes
    });

    test('引用卡片SVG生成和图片转换', () async {
      final svgContent = CardTemplates.quoteTemplate(
        content: '生活不是等待暴风雨过去，而是学会在雨中跳舞。',
        author: '维维安·格林',
        date: '2024年1月15日',
      );

      final card = GeneratedCard(
        id: 'test_card_2',
        noteId: 'note_2',
        originalContent: '生活不是等待暴风雨过去，而是学会在雨中跳舞。',
        svgContent: svgContent,
        type: CardType.quote,
        createdAt: DateTime.now(),
      );

      final imageBytes = await card.toImageBytes();

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 引用卡片图片大小: ${imageBytes.length} bytes
    });

    test('哲学卡片SVG生成和图片转换', () async {
      final svgContent = CardTemplates.philosophicalTemplate(
        content: '人生的意义在于不断地思考和探索，每一次的反思都让我们更接近真理。',
        author: '苏格拉底',
        date: '2024年1月15日',
      );

      final card = GeneratedCard(
        id: 'test_card_3',
        noteId: 'note_3',
        originalContent: '人生的意义在于不断地思考和探索，每一次的反思都让我们更接近真理。',
        svgContent: svgContent,
        type: CardType.philosophical,
        createdAt: DateTime.now(),
      );

      final imageBytes = await card.toImageBytes();

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 哲学卡片图片大小: ${imageBytes.length} bytes
    });

    test('简约卡片SVG生成和图片转换', () async {
      final svgContent = CardTemplates.minimalistTemplate(
        content: '简约而不简单，这是设计的最高境界。',
        author: '达芬奇',
        date: '2024年1月15日',
      );

      final card = GeneratedCard(
        id: 'test_card_4',
        noteId: 'note_4',
        originalContent: '简约而不简单，这是设计的最高境界。',
        svgContent: svgContent,
        type: CardType.minimalist,
        createdAt: DateTime.now(),
      );

      final imageBytes = await card.toImageBytes();

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 简约卡片图片大小: ${imageBytes.length} bytes
    });

    test('高分辨率图片转换', () async {
      final svgContent = CardTemplates.knowledgeTemplate(
        content: '高分辨率测试内容',
        date: '2024年1月15日',
      );

      final card = GeneratedCard(
        id: 'test_card_hd',
        noteId: 'note_hd',
        originalContent: '高分辨率测试内容',
        svgContent: svgContent,
        type: CardType.knowledge,
        createdAt: DateTime.now(),
      );

      // 生成高分辨率图片
      final imageBytes = await card.toImageBytes(width: 800, height: 1200);

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 高分辨率卡片图片大小: ${imageBytes.length} bytes

      // 高分辨率图片应该比标准分辨率大
      final standardImageBytes = await card.toImageBytes();
      expect(imageBytes.length, greaterThan(standardImageBytes.length));
    });

    test('批量卡片转换性能测试', () async {
      final cards = <GeneratedCard>[];

      // 创建多个卡片
      for (int i = 0; i < 3; i++) {
        final svgContent = CardTemplates.knowledgeTemplate(
          content: '测试内容 $i：这是第${i + 1}张测试卡片的内容。',
          date: '2024年1月15日',
        );

        cards.add(
          GeneratedCard(
            id: 'test_card_$i',
            noteId: 'note_$i',
            originalContent: '测试内容 $i：这是第${i + 1}张测试卡片的内容。',
            svgContent: svgContent,
            type: CardType.knowledge,
            createdAt: DateTime.now(),
          ),
        );
      }

      final stopwatch = Stopwatch()..start();

      // 批量转换
      final results = <Uint8List>[];
      for (final card in cards) {
        final imageBytes = await card.toImageBytes();
        results.add(imageBytes);
      }

      stopwatch.stop();

      expect(results.length, equals(3));
      for (final result in results) {
        expect(result, isNotNull);
        expect(result.length, greaterThan(0));
      }

      // Test output: 批量转换3张卡片耗时: ${stopwatch.elapsedMilliseconds}ms
      expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // 应该在10秒内完成
    });

    test('错误SVG处理', () async {
      final card = GeneratedCard(
        id: 'test_card_error',
        noteId: 'note_error',
        originalContent: '错误SVG测试',
        svgContent: '<invalid>这不是有效的SVG</invalid>',
        type: CardType.knowledge,
        createdAt: DateTime.now(),
      );

      // 即使SVG无效，也应该返回错误图片而不是抛出异常
      final imageBytes = await card.toImageBytes();

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 错误SVG处理图片大小: ${imageBytes.length} bytes
    });
  });
}
